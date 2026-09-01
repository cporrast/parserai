require "digest"

module Scraping
  class SchemaRecommender
    Result = Data.define(:schema, :cached)
    MAX_TEXT_LENGTH = 24_000
    MAX_STRUCTURE_LENGTH = 24_000

    def initialize(page_cache: SetupPageCache.new, client: nil)
      @page_cache = page_cache
      @client = client
    end

    def recommend(url:, instructions:, current_schema:, model:, loggable: nil, async_operation: nil)
      page = @page_cache.fetch(url)
      cache_key = build_cache_key(page, instructions:, current_schema:, model:)
      cached_result = cached_recommendation(page, cache_key)
      return cached_result if cached_result

      response = client.chat(
        model:, json: true, temperature: 0.1,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt(page, instructions:, current_schema:) }
        ],
        loggable:, purpose: "schema_recommendation", async_operation:
      )
      schema = parse_schema(response.content)
      formatted_schema = JSON.pretty_generate(schema)

      page.update!(
        suggested_schema: formatted_schema,
        schema_cache_key: cache_key,
        schema_generated_at: Time.current
      )
      Result.new(schema: formatted_schema, cached: false)
    rescue Llm::JsonResponse::ParseError => e
      raise InvalidRecommendation, "The model returned invalid schema JSON: #{e.message}"
    end

    private

    def client
      @client ||= Llm::Client.new
    end

    def build_cache_key(page, instructions:, current_schema:, model:)
      Digest::SHA256.hexdigest(
        [ page.content_digest.presence || page.fetched_at.to_f, instructions, current_schema, model ].join("\0")
      )
    end

    def cached_recommendation(page, cache_key)
      return unless page.schema_cache_key == cache_key && page.suggested_schema.present?

      parse_schema(page.suggested_schema)
      Result.new(schema: page.suggested_schema, cached: true)
    rescue Llm::JsonResponse::ParseError, InvalidRecommendation
      nil
    end

    def parse_schema(content)
      schema = Llm::JsonResponse.parse(content)
      unless schema.is_a?(Hash)
        raise InvalidRecommendation, "The suggested schema must be a JSON object"
      end

      schema
    end

    def system_prompt
      <<~PROMPT.strip
        You design practical JSON Schemas for extracting structured data from web pages.
        Return only a valid draft-07-compatible JSON Schema object. Do not include markdown.
        Keep the schema grounded in the supplied page and extraction instructions.
      PROMPT
    end

    def user_prompt(page, instructions:, current_schema:)
      <<~PROMPT.strip
        Recommend the JSON Schema for this extraction workflow.

        Page URL: #{page.final_url.presence || page.url}
        Page title: #{page.title.presence || "Unknown"}
        Extraction instructions: #{instructions}
        Current schema or example:
        #{current_schema.presence || "None"}

        Readable page text:
        ---
        #{page.extracted_text.to_s.truncate(MAX_TEXT_LENGTH)}
        ---

        Parsed page structure:
        ---
        #{JSON.pretty_generate(page.structured_data || {}).truncate(MAX_STRUCTURE_LENGTH)}
        ---
      PROMPT
    end
  end
end
