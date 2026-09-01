require "digest"

module Scraping
  class SelectorRuleRecommender
    Result = Data.define(:rules, :cached, :matched_items)
    MAX_ATTEMPTS = 2
    MAX_STRUCTURE_LENGTH = 16_000

    def initialize(page_cache: SetupPageCache.new, client: nil)
      @page_cache = page_cache
      @client = client
    end

    def recommend(url:, instructions:, output_schema:, model:, loggable: nil, async_operation: nil)
      page = @page_cache.fetch(url)
      cache_key = build_cache_key(page, instructions:, output_schema:, model:)
      cached_result = cached_recommendation(page, cache_key)
      return cached_result if cached_result

      rules, matched_items = generate_valid_rules(
        page, instructions:, output_schema:, model:, loggable:, async_operation:
      )
      formatted_rules = JSON.pretty_generate(rules)
      page.update!(
        suggested_rules: formatted_rules,
        selector_rules_cache_key: cache_key,
        selector_rules_generated_at: Time.current
      )

      Result.new(rules: formatted_rules, cached: false, matched_items:)
    end

    private

    def client
      @client ||= Llm::Client.new
    end

    def build_cache_key(page, instructions:, output_schema:, model:)
      Digest::SHA256.hexdigest(
        [ page.content_digest.presence || page.fetched_at.to_f, instructions, output_schema, model ].join("\0")
      )
    end

    def cached_recommendation(page, cache_key)
      return unless page.selector_rules_cache_key == cache_key && page.suggested_rules.present?

      rule_set = SelectorRuleSet.new(page.suggested_rules)
      matched_items = test_rules(page, rule_set)
      return if matched_items.zero?

      Result.new(rules: page.suggested_rules, cached: true, matched_items:)
    rescue SelectorRuleSet::InvalidRules, SelectorExtractor::ExtractionError
      nil
    end

    def generate_valid_rules(page, instructions:, output_schema:, model:, loggable:, async_operation:)
      previous_response = nil
      validation_error = nil

      MAX_ATTEMPTS.times do
        response = client.chat(
          model:, json: true, temperature: 0.1,
          messages: recommendation_messages(
            page, instructions:, output_schema:, previous_response:, validation_error:
          ),
          loggable:, purpose: "selector_rule_recommendation", async_operation:
        )
        previous_response = response.content

        begin
          rule_set = parse_rule_set(response.content)
          matched_items = test_rules(page, rule_set)
          if matched_items.zero?
            raise InvalidRecommendation, "item_selector did not match any elements in the page"
          end

          return [ rule_set.rules, matched_items ]
        rescue Llm::JsonResponse::ParseError, SelectorRuleSet::InvalidRules,
               SelectorExtractor::ExtractionError, InvalidRecommendation => e
          validation_error = e.message
        end
      end

      raise InvalidRecommendation,
        "The model could not produce executable selector rules: #{validation_error}"
    end

    def parse_rule_set(content)
      SelectorRuleSet.new(Llm::JsonResponse.parse(content))
    end

    def test_rules(page, rule_set)
      SelectorExtractor.new(rule_set).extract(
        html: page.raw_html,
        base_url: page.final_url.presence || page.url
      ).matched_items
    end

    def recommendation_messages(page, instructions:, output_schema:, previous_response:, validation_error:)
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(page, instructions:, output_schema:) }
      ]
      return messages if previous_response.blank?

      messages.concat([
        { role: "assistant", content: previous_response },
        { role: "user", content: correction_prompt(validation_error) }
      ])
    end

    def system_prompt
      <<~PROMPT.strip
        You create one executable Nokogiri selector rule set for a server-rendered HTML page.
        Return only one JSON object with exactly these top-level keys:
        - "selector_type": "css" or "xpath"
        - "item_selector": one selector that matches every repeated record
        - "output_key": the name of the output array
        - "fields": one flat object of field configurations

        Every field configuration may contain only: selector, selector_type, value, attribute,
        multiple, resolve_url, and transforms. Supported values are text, html, and attribute.
        Supported transforms are strip, squish, downcase, upcase, integer, float, and boolean.

        Rules are flat: never put item_selector, fields, or nested field objects inside a field.
        Flatten nested requested data into useful scalar or multiple-value fields.
        Use only selectors visibly grounded in the supplied HTML. Do not invent class names.
        Prefer stable semantic attributes, ids, and human-readable classes over positional selectors
        or generated-looking class names. Field selectors run inside each matched item. XPath field
        selectors must start with .// rather than // so they remain scoped to that item.
        Use multiple: true when a field intentionally returns more than one element.
      PROMPT
    end

    def user_prompt(page, instructions:, output_schema:)
      <<~PROMPT.strip
        Recommend executable extraction rules for this page.

        URL: #{page.final_url.presence || page.url}
        Desired information: #{instructions.presence || "Infer useful repeated records."}
        Desired output structure: #{output_schema.presence || "An items array."}

        Cleaned body HTML:
        ---
        #{SelectorHtmlSample.new(page.raw_html)}
        ---

        Parsed links, images, metadata, and structured content:
        ---
        #{JSON.pretty_generate(page.structured_data || {}).truncate(MAX_STRUCTURE_LENGTH)}
        ---
      PROMPT
    end

    def correction_prompt(validation_error)
      <<~PROMPT.strip
        Those rules cannot be executed: #{validation_error}.
        Return a corrected flat rule set in the exact required shape. Use a selector that matches
        at least one element shown in the supplied HTML. Return JSON only.
      PROMPT
    end
  end
end
