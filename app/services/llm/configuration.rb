module Llm
  class Configuration
    DEFAULT_BASE_URL = "https://openrouter.ai/api/v1"
    DEFAULT_MODEL = "openrouter/auto"
    MODEL_ENV_KEYS = {
      extraction: "EXTRACTION_MODEL",
      setup: "SETUP_MODEL",
      chat: "CHAT_MODEL"
    }.freeze

    class << self
      def api_key
        ENV["OPENROUTER_API_KEY"].presence || ENV["LLM_API_KEY"].presence
      end

      def base_url
        ENV.fetch("LLM_BASE_URL", DEFAULT_BASE_URL)
      end

      def model_for(role)
        key = MODEL_ENV_KEYS.fetch(role)
        ENV[key].presence || DEFAULT_MODEL
      end

      def request_headers
        {
          "HTTP-Referer" => ENV["OPENROUTER_SITE_URL"].presence,
          "X-Title" => ENV.fetch("OPENROUTER_APP_NAME", "ParserAI").presence
        }.compact
      end
    end
  end
end
