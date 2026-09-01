module Scraping
  class LlmExtractor
    Result = Data.define(:data, :raw_response, :usage, :model, :prompt)
    MAX_STRUCTURED_LENGTH = ENV.fetch("SCRAPER_MAX_STRUCTURED_PROMPT_LENGTH", 60_000).to_i
    MAX_RAW_HTML_LENGTH = ENV.fetch("SCRAPER_MAX_RAW_HTML_PROMPT_LENGTH", 100_000).to_i

    class InvalidResponse < StandardError
      attr_reader :llm_result

      def initialize(message, llm_result: nil)
        @llm_result = llm_result
        super(message)
      end
    end

    def initialize(client: Llm::Client.new)
      @client = client
    end

    def extract(source:, instructions:, definition:, model:, content_strategy: "standard", loggable: nil,
                scrape_execution: nil)
      prompt = build_prompt(source:, instructions:, definition:, content_strategy:)
      llm_result = @client.chat(
        model:,
        json: true,
        temperature: 0.1,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: prompt }
        ],
        loggable:, purpose: "page_extraction", scrape_execution:, scrape_source: source
      )
      data = Llm::JsonResponse.parse(llm_result.content)
      validate_shape!(data, definition)

      Result.new(
        data:,
        raw_response: llm_result.raw,
        usage: llm_result.usage,
        model: llm_result.model,
        prompt:
      )
    rescue Llm::JsonResponse::ParseError => e
      raise InvalidResponse.new("The model did not return valid JSON: #{e.message}", llm_result:)
    rescue InvalidResponse => e
      raise InvalidResponse.new(e.message, llm_result: e.llm_result || llm_result)
    end

    private

    def system_prompt
      <<~PROMPT.strip
        You extract structured data from web-page text. Follow the user's extraction instructions exactly.
        Return only valid JSON. Do not wrap it in markdown. Do not invent facts; use null when information is absent.
        Keep values concise and preserve source wording where useful.
      PROMPT
    end

    def build_prompt(source:, instructions:, definition:, content_strategy:)
      <<~PROMPT.strip
        Extract information from this page.

        Page URL: #{source.final_url.presence || source.url}
        Page title: #{source.title.presence || "Unknown"}

        Extraction instructions:
        #{instructions}

        Required JSON output:
        #{definition.prompt_description}

        Content strategy: #{content_strategy.humanize}
        Page representation:
        ---
        #{page_representation(source, content_strategy)}
        ---
      PROMPT
    end

    def page_representation(source, content_strategy)
      case content_strategy
      when "visible_text"
        "READABLE PAGE TEXT:\n#{source.extracted_text}"
      when "metadata"
        "STRUCTURED HTML DATA:\n#{structured_json(metadata_subset(source.structured_data))}"
      when "raw_html"
        "RAW HTML:\n#{source.raw_html.to_s.truncate(MAX_RAW_HTML_LENGTH, omission: "\n[Raw HTML truncated by ParserAI]")}"
      else
        <<~CONTENT.strip
          READABLE PAGE TEXT:
          #{source.extracted_text}

          STRUCTURED HTML DATA (attributes and machine-readable content may not be visible on the page):
          #{structured_json(source.structured_data)}
        CONTENT
      end
    end

    def metadata_subset(data)
      value = data.is_a?(Hash) ? data : {}
      value.slice("metadata", "links", "images", "json_ld", "embedded_json", "microdata", "data_attributes", "labeled_elements", "hidden_content")
    end

    def structured_json(data)
      JSON.pretty_generate(data || {}).truncate(MAX_STRUCTURED_LENGTH, omission: "\n[Structured data truncated by ParserAI]")
    end

    def validate_shape!(data, definition)
      if definition.json?
        validate_json_shape!(data, definition.parsed)
        return
      end

      unless data.is_a?(Hash) && data["rows"].is_a?(Array)
        raise InvalidResponse, "CSV workflows must return a JSON object containing a rows array"
      end

      columns = definition.csv_columns
      data["rows"] = data["rows"].filter_map do |row|
        next unless row.is_a?(Hash)
        columns.index_with { |column| row[column] }
      end
    end

    def validate_json_shape!(data, specification)
      return unless specification.is_a?(Hash) && specification["type"].present?

      expected_class = { "object" => Hash, "array" => Array }[specification["type"]]
      if expected_class && !data.is_a?(expected_class)
        raise InvalidResponse, "The model response does not match the requested top-level #{specification["type"]}"
      end

      return unless data.is_a?(Hash) && specification["required"].is_a?(Array)

      missing = specification["required"].reject { |key| data.key?(key) }
      raise InvalidResponse, "The model response is missing required fields: #{missing.join(", ")}" if missing.any?
    end
  end
end
