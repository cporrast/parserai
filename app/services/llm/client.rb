require "openai"

module Llm
  class Client
    Result = Data.define(:content, :raw, :usage, :model)

    class ConfigurationError < StandardError; end
    class ResponseError < StandardError; end

    def self.configured?
      Configuration.api_key.present?
    end

    def initialize(api_key: Configuration.api_key,
                   base_url: Configuration.base_url,
                   extra_headers: Configuration.request_headers,
                   request_timeout: ENV.fetch("LLM_REQUEST_TIMEOUT", 180).to_i,
                   client: nil)
      if client.nil? && api_key.blank?
        raise ConfigurationError, "Set OPENROUTER_API_KEY (or LLM_API_KEY) before running AI workflows"
      end

      @base_url = base_url.delete_suffix("/")
      @client = client || OpenAI::Client.new(
        access_token: api_key,
        uri_base: @base_url,
        extra_headers:,
        request_timeout: request_timeout,
        log_errors: false
      )
    end

    def chat(messages:, model:, json: false, temperature: 0.1, loggable: nil, purpose: "chat",
             scrape_execution: nil, scrape_source: nil, async_operation: nil)
      parameters = { model:, messages: PromptBudget.new.apply(messages), temperature: }
      parameters[:response_format] = { type: "json_object" } if json
      started_at = Time.current
      started_clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      request_log = create_request_log(
        loggable:, purpose:, scrape_execution:, scrape_source:, async_operation:, parameters:, started_at:
      )
      response = nil

      response = @client.chat(parameters:)
      raise ResponseError, "The provider returned an unreadable response" unless response.is_a?(Hash)
      raise ResponseError, provider_error(response) if response["error"].present?

      content = response.dig("choices", 0, "message", "content")
      raise ResponseError, "The model returned an empty response" if content.blank?

      returned_model = response["model"] || model
      usage = response["usage"] || {}
      finish_request_log(request_log, response:, returned_model:, usage:, started_clock:)
      Result.new(content:, raw: response, usage:, model: returned_model)
    rescue Faraday::Error => e
      error = ResponseError.new("LLM request failed: #{e.message}")
      fail_request_log(request_log, response:, error:, started_clock:)
      raise error
    rescue StandardError => e
      fail_request_log(request_log, response:, error: e, started_clock:)
      raise
    end

    private

    def provider_error(response)
      error = response["error"]
      message = error.is_a?(Hash) ? error["message"] : error.to_s
      "OpenRouter request failed: #{message.presence || "unknown provider error"}"
    end

    def create_request_log(loggable:, purpose:, scrape_execution:, scrape_source:, async_operation:, parameters:, started_at:)
      return unless loggable&.persisted?

      LlmRequest.create!(
        loggable:, purpose:, scrape_execution:, scrape_source:, async_operation:,
        provider: "openrouter", endpoint: "#{@base_url}/chat/completions",
        model_requested: parameters[:model], request_payload: parameters.deep_stringify_keys,
        status: "pending", started_at:
      )
    rescue StandardError => e
      Rails.logger.error("Could not create LLM request log: #{e.class}: #{e.message}")
      nil
    end

    def finish_request_log(request_log, response:, returned_model:, usage:, started_clock:)
      return unless request_log

      request_log.update!(
        status: "completed", response_payload: serializable_payload(response),
        model_returned: returned_model, provider_request_id: response["id"], usage:,
        completed_at: Time.current, duration_ms: elapsed_ms(started_clock)
      )
    rescue StandardError => e
      Rails.logger.error("Could not complete LLM request log: #{e.class}: #{e.message}")
    end

    def fail_request_log(request_log, response:, error:, started_clock:)
      return unless request_log

      request_log.update!(
        status: "failed", response_payload: serializable_payload(response),
        provider_request_id: response.is_a?(Hash) ? response["id"] : nil,
        model_returned: response.is_a?(Hash) ? response["model"] : nil,
        usage: response.is_a?(Hash) ? response["usage"] : nil,
        error_class: error.class.name, error_message: error.message.to_s.truncate(10_000),
        completed_at: Time.current, duration_ms: elapsed_ms(started_clock)
      )
    rescue StandardError => log_error
      Rails.logger.error("Could not fail LLM request log: #{log_error.class}: #{log_error.message}")
    end

    def serializable_payload(payload)
      payload&.as_json
    rescue StandardError
      payload.inspect
    end

    def elapsed_ms(started_clock)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_clock) * 1_000).round
    end
  end
end
