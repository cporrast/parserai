require "test_helper"

class ProjectWorkflowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "saves and edits a workflow without running it" do
    project = Project.create!(name: "My research")

    assert_no_enqueued_jobs do
      post project_scrape_runs_path(project), params: {
        scrape_run: workflow_params
      }
    end

    workflow = project.scrape_runs.last
    assert_redirected_to scrape_run_path(workflow)
    assert_equal 0, workflow.scrape_executions.count
    assert_equal 2, workflow.urls.size

    patch scrape_run_path(workflow), params: {
      scrape_run: workflow_params.merge(instructions: "Extract title and price")
    }
    assert_redirected_to scrape_run_path(workflow)
    assert_equal "Extract title and price", workflow.reload.instructions
    assert_equal "anthropic/setup-model", workflow.setup_model
    assert_equal "google/extraction-model", workflow.extraction_model
    assert_equal 0, workflow.scrape_executions.count
  end

  test "explicit run action snapshots the workflow and queues an execution" do
    workflow = create_workflow

    with_api_key do
      assert_enqueued_with(job: ProcessScrapeExecutionJob) do
        post execute_scrape_run_path(workflow)
      end
    end

    execution = workflow.scrape_executions.last
    assert_redirected_to scrape_execution_path(execution)
    assert_equal workflow.instructions, execution.instructions
    assert_equal workflow.content_strategy, execution.content_strategy
    assert_equal workflow.extraction_model, execution.extraction_model
    assert_equal workflow.urls, execution.scrape_sources.order(:position).pluck(:url)
  end

  test "selector workflow runs without an api key and snapshots its rules" do
    rules = '{"item_selector":"a[href]","fields":{"url":{"value":"attribute","attribute":"href"}}}'
    workflow = create_workflow
    workflow.update!(processing_mode: "selectors", selector_rules: rules)

    assert_enqueued_with(job: ProcessScrapeExecutionJob) { post execute_scrape_run_path(workflow) }

    execution = workflow.scrape_executions.last
    assert_redirected_to scrape_execution_path(execution)
    assert_equal "selectors", execution.processing_mode
    assert_equal rules, execution.selector_rules
  end

  test "schema recommendation, selector recommendation, preview, and prefetch are separate workflows" do
    workflow = create_workflow
    project = workflow.project
    url = "https://example.com/products"
    page = SetupPageSnapshot.create!(
      url_digest: Digest::SHA256.hexdigest(url), url:, final_url: url,
      raw_html: '<article class="product"><a href="/one"><span class="name">One</span></a></article>',
      extracted_text: "One", structured_data: {}, fetched_at: Time.current
    )
    recommended_schema = '{"type":"object"}'
    recommended_rules = JSON.generate(
      selector_type: "css", item_selector: ".product", output_key: "products",
      fields: { name: { selector: ".name", value: "text" } }
    )
    page.update!(
      suggested_schema: recommended_schema,
      schema_cache_key: Digest::SHA256.hexdigest(
        [ page.fetched_at.to_f, "Collect products", "{}", "test/schema" ].join("\0")
      ),
      suggested_rules: recommended_rules,
      selector_rules_cache_key: Digest::SHA256.hexdigest(
        [ page.fetched_at.to_f, "Collect products", "{}", "test/selectors" ].join("\0")
      )
    )

    post suggest_schema_project_scrape_runs_path(project), params: {
      url:, instructions: "Collect products", output_schema: "{}",
      setup_model: "test/schema", scrape_run_id: workflow.id
    }
    assert_response :accepted
    schema_result = complete_latest_operation
    assert_equal({ "type" => "object" }, JSON.parse(schema_result.fetch("schema")))
    refute schema_result.key?("rules")

    post suggest_rules_project_scrape_runs_path(project), params: {
      url:, instructions: "Collect products", output_schema: "{}",
      setup_model: "test/selectors", scrape_run_id: workflow.id
    }
    assert_response :accepted
    rules_result = complete_latest_operation
    assert_equal 1, rules_result.fetch("matched_items")
    assert_equal ".product", JSON.parse(rules_result.fetch("rules"))["item_selector"]
    refute rules_result.key?("schema")

    post test_rules_project_scrape_runs_path(project), params: {
      url:, instructions: "Collect products", output_schema: "{}",
      selector_rules: recommended_rules, output_format: "json"
    }
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("matched_items")
    assert_equal "One", response.parsed_body.dig("data", "products", 0, "name")
    assert_equal "One", response.parsed_body.dig("final_data", "sources", 0, "data", "products", 0, "name")
    assert_equal 1, response.parsed_body.dig("diagnostics", "emitted_records")
    assert_includes response.parsed_body.fetch("preview_html"), "data-parserai-item"
    assert_equal url, response.parsed_body.dig("page", "url")

    post test_rules_project_scrape_runs_path(project), params: {
      url:, instructions: "Collect products", output_schema: "name",
      selector_rules: recommended_rules, output_format: "csv"
    }
    assert_response :success
    assert_equal "name\nOne\n", response.parsed_body.fetch("preview_text")

    post prefetch_setup_project_scrape_runs_path(project), params: { url:, scrape_run_id: workflow.id }
    assert_response :accepted
    assert complete_latest_operation.fetch("cached")
    assert_equal workflow, AsyncOperation.where(kind: "setup_prefetch").last.operable
  end

  test "exports completed JSON and CSV execution outputs" do
    json_workflow = create_workflow
    json_execution = create_execution(json_workflow)
    json_output = json_execution.extraction_outputs.create!(scrape_run: json_workflow, kind: "combined", data: { "name" => "Widget" }, generated_at: Time.current)

    get export_extraction_output_path(json_output)
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_includes response.body, "Widget"

    csv_workflow = create_workflow(output_format: "csv", output_schema: "name,price")
    csv_execution = create_execution(csv_workflow)
    csv_output = csv_execution.extraction_outputs.create!(scrape_run: csv_workflow, kind: "combined", data: { "rows" => [ { "price" => 12, "name" => "Widget" } ] }, generated_at: Time.current)

    get export_extraction_output_path(csv_output)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal "name,price\nWidget,12\n", response.body
  end

  test "project chat queues a background operation without waiting for the provider" do
    project = Project.create!(name: "Questions")

    assert_enqueued_with(job: ProcessAsyncOperationJob) do
      post project_chat_messages_path(project), params: {
        idempotency_key: "chat-request-1",
        chat_message: { content: "What changed?" }
      }
    end

    operation = project.async_operations.last
    assert_redirected_to project_path(project, operation_id: operation.id, anchor: "chat")
    assert_equal "project_chat", operation.kind
    assert_equal "What changed?", project.chat_messages.last.content
  end

  test "renders workflow setup and immutable execution screens" do
    workflow = create_workflow
    execution = create_execution(workflow, status: "completed")
    source = execution.scrape_sources.create!(
      scrape_run: workflow,
      url: "https://example.com/product",
      final_url: "https://example.com/product",
      title: "Example product",
      status: "completed",
      http_status: 200,
      content_type: "text/html",
      raw_html: "<html><body>Widget</body></html>",
      extracted_text: "Widget $12",
      fetched_at: Time.current
    )
    output = execution.extraction_outputs.create!(
      scrape_run: workflow,
      scrape_source: source,
      kind: "source",
      data: { "name" => "Widget", "price" => 12 },
      usage: { "total_tokens" => 20 },
      generated_at: Time.current
    )
    execution.extraction_outputs.create!(scrape_run: workflow, kind: "combined", data: { "sources" => [ { "url" => source.url, "data" => output.data } ] }, generated_at: Time.current)
    request_log = workflow.llm_requests.create!(
      purpose: "page_extraction", provider: "openrouter", endpoint: "https://openrouter.ai/api/v1/chat/completions",
      model_requested: "test-model", model_returned: "test-model", status: "completed",
      request_payload: { model: "test-model", messages: [ { role: "user", content: "Extract data" } ] },
      response_payload: { id: "generation-1", choices: [] }, usage: { total_tokens: 20 },
      scrape_execution: execution, scrape_source: source, started_at: Time.current, completed_at: Time.current, duration_ms: 50
    )

    [ root_path, project_path(workflow.project), new_project_scrape_run_path(workflow.project), edit_scrape_run_path(workflow), scrape_run_path(workflow), scrape_execution_path(execution), scrape_source_path(source), extraction_output_path(output), llm_request_path(request_log) ].each do |path|
      get path
      assert_response :success, "Expected #{path} to render"
    end

    get scrape_run_path(workflow)
    assert_includes response.body, "Task API activity"
    assert_includes response.body, "Page extraction"

    get llm_request_path(request_log)
    assert_includes response.body, "Submitted API request and prompts"
    assert_includes response.body, "Extract data"
    assert_includes response.body, "generation-1"
  end

  private

  def workflow_params
    {
      urls_text: "https://example.com/one\nhttps://example.com/two",
      instructions: "Extract the title",
      output_format: "json",
      output_schema: '{"title":"string"}',
      setup_model: "anthropic/setup-model",
      extraction_model: "google/extraction-model",
      recurrence: "manual"
    }
  end

  def create_workflow(output_format: "json", output_schema: '{"name":"string"}')
    Project.create!(name: "Research #{SecureRandom.hex(2)}").scrape_runs.create!(
      workflow_params.merge(output_format:, output_schema:)
    )
  end

  def create_execution(workflow, status: "queued")
    workflow.scrape_executions.create!(
      status:,
      instructions: workflow.instructions,
      output_format: workflow.output_format,
      output_schema: workflow.output_schema,
      extraction_model: "test-model"
    )
  end

  def with_api_key
    previous = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = "test-key"
    yield
  ensure
    ENV["OPENROUTER_API_KEY"] = previous
  end

  def complete_latest_operation
    operation = AsyncOperation.last
    perform_enqueued_jobs(only: ProcessAsyncOperationJob)
    get async_operation_path(operation), as: :json
    assert_response :success
    assert_equal "completed", response.parsed_body.fetch("status")
    response.parsed_body.fetch("result")
  end
end
