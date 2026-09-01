module Llm
  class JsonResponse
    class ParseError < StandardError; end

    def self.parse(content)
      cleaned_content = content.to_s.strip
        .sub(/\A```(?:json)?\s*/i, "")
        .sub(/\s*```\z/, "")

      JSON.parse(cleaned_content)
    rescue JSON::ParserError => e
      raise ParseError, e.message
    end
  end
end
