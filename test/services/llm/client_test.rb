require "test_helper"

class Llm::ClientTest < ActiveSupport::TestCase
  class FakeProviderClient
    attr_reader :parameters

    def initialize(response)
      @response = response
    end

    def chat(parameters:)
      @parameters = parameters
      @response
    end
  end

  test "records the complete request and response with workflow context" do
    run, execution, source = workflow_context
    operation = run.async_operations.create!(
      kind: "schema_recommendation",
      idempotency_key: SecureRandom.uuid,
      input: { url: source.url }
    )
    provider = FakeProviderClient.new(
      "id" => "generation-123",
      "model" => "vendor/returned-model",
      "choices" => [ { "message" => { "content" => '{"title":"Example"}' } } ],
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 4, "total_tokens" => 14 }
    )
    client = Llm::Client.new(client: provider)

    result = client.chat(
      model: "vendor/requested-model", json: true,
      messages: [ { role: "user", content: "Extract the title" } ],
      loggable: run, purpose: "page_extraction", scrape_execution: execution, scrape_source: source,
      async_operation: operation
    )

    request_log = run.llm_requests.last
    assert_equal "vendor/returned-model", result.model
    assert request_log.completed?
    assert_equal execution, request_log.scrape_execution
    assert_equal source, request_log.scrape_source
    assert_equal operation, request_log.async_operation
    assert_equal "Extract the title", request_log.request_payload.dig("messages", 0, "content")
    assert_equal "json_object", request_log.request_payload.dig("response_format", "type")
    assert_equal "generation-123", request_log.provider_request_id
    assert_equal 14, request_log.usage["total_tokens"]
    assert_equal "vendor/returned-model", request_log.model_returned
    assert request_log.duration_ms >= 0
    refute_includes request_log.request_payload.to_json, "api_key"
  end

  test "records provider errors and the raw error response" do
    project = Project.create!(name: "Debugging")
    provider = FakeProviderClient.new(
      "id" => "generation-failed",
      "error" => { "message" => "No provider capacity" }
    )
    client = Llm::Client.new(client: provider)

    error = assert_raises(Llm::Client::ResponseError) do
      client.chat(
        model: "vendor/model", messages: [ { role: "user", content: "Hello" } ],
        loggable: project, purpose: "project_chat"
      )
    end

    request_log = project.llm_requests.last
    assert_includes error.message, "No provider capacity"
    assert request_log.failed?
    assert_equal "generation-failed", request_log.provider_request_id
    assert_equal "No provider capacity", request_log.response_payload.dig("error", "message")
    assert_equal "Llm::Client::ResponseError", request_log.error_class
    assert_includes request_log.error_message, "No provider capacity"
  end

  private

  def workflow_context
    run = Project.create!(name: "Catalog").scrape_runs.create!(
      urls_text: "https://example.com", instructions: "Extract the title",
      output_format: "json", output_schema: '{"title":"string"}'
    )
    execution = run.scrape_executions.create!(
      instructions: run.instructions, output_format: run.output_format,
      output_schema: run.output_schema, extraction_model: "vendor/requested-model"
    )
    source = execution.scrape_sources.create!(
      scrape_run: run, url: "https://example.com", position: 0
    )
    [ run, execution, source ]
  end
end
