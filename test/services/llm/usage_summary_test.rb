require "test_helper"

class Llm::UsageSummaryTest < ActiveSupport::TestCase
  test "aggregates provider reported tokens cost latency and models" do
    project = Project.create!(name: "Metrics")
    project.llm_requests.create!(
      purpose: "project_chat", provider: "openrouter", endpoint: "https://example.test",
      model_requested: "vendor/model-a", model_returned: "vendor/model-a", status: "completed",
      request_payload: {}, usage: { prompt_tokens: 10, completion_tokens: 4, total_tokens: 14, cost: 0.0012 },
      started_at: Time.current, completed_at: Time.current, duration_ms: 100
    )
    project.llm_requests.create!(
      purpose: "project_chat", provider: "openrouter", endpoint: "https://example.test",
      model_requested: "vendor/model-b", status: "failed", request_payload: {},
      usage: { prompt_tokens: 5, completion_tokens: 0, total_tokens: 5 },
      started_at: Time.current, completed_at: Time.current, duration_ms: 300
    )

    summary = Llm::UsageSummary.new(project.llm_requests)

    assert_equal 2, summary.request_count
    assert_equal 1, summary.failed_count
    assert_equal 15, summary.prompt_tokens
    assert_equal 19, summary.total_tokens
    assert_in_delta 0.0012, summary.cost
    assert_equal 200, summary.average_duration_ms
    assert_equal({ "vendor/model-a" => 1, "vendor/model-b" => 1 }, summary.models)
  end
end
