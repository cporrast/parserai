require "test_helper"

class Scraping::ProcessExecutionTest < ActiveSupport::TestCase
  FakeFetcher = Struct.new(:pages) do
    def fetch(url, **)
      page = pages.fetch(url)
      raise Scraping::PageFetcher::FetchError, page if page.is_a?(String) && !page.start_with?("<")

      Scraping::PageFetcher::Result.new(url:, status: 200, content_type: "text/html", body: page)
    end
  end

  class FakeLlmClient
    def chat(messages:, model:, **)
      title = messages.last[:content].include?("First") ? "First" : "Second"
      body = { "items" => [ { "title" => title } ] }
      Llm::Client::Result.new(
        content: JSON.generate(body),
        raw: { "model" => model, "choices" => [ { "message" => { "content" => JSON.generate(body) } } ] },
        usage: { "total_tokens" => 42 },
        model:
      )
    end
  end

  test "stores snapshots, per-source output, and a combined result" do
    project = Project.create!(name: "Products")
    run = project.scrape_runs.create!(
      urls_text: "https://example.com/one\nhttps://example.com/two",
      instructions: "Collect each title",
      output_format: "json",
      output_schema: '{"type":"object","properties":{"items":{"type":"array"}}}'
    )
    execution = create_execution(run)
    execution.scrape_sources.create!(scrape_run: run, url: "https://example.com/one", position: 0)
    execution.scrape_sources.create!(scrape_run: run, url: "https://example.com/two", position: 1)
    fetcher = FakeFetcher.new({
      "https://example.com/one" => "<html><title>First</title><body><main>First page</main></body></html>",
      "https://example.com/two" => "<html><title>Second</title><body><main>Second page</main></body></html>"
    })

    Scraping::ProcessExecution.new(execution, fetcher:, llm_client: FakeLlmClient.new).call

    assert execution.reload.completed?
    assert_equal 2, execution.scrape_sources.where(status: "completed").count
    assert_equal 2, execution.extraction_outputs.where(kind: "source", status: "completed").count
    assert_equal 2, execution.combined_output.data["sources"].size
    assert_includes execution.scrape_sources.first.raw_html, "First page"
    assert_equal "First", execution.scrape_sources.first.structured_data.dig("metadata", "title")
  end

  test "keeps successful pages when another source fails" do
    project = Project.create!(name: "Mixed")
    run = project.scrape_runs.create!(
      urls_text: "https://example.com/good\nhttps://example.com/bad",
      instructions: "Collect titles",
      output_format: "json",
      output_schema: '{"items":[]}'
    )
    execution = create_execution(run)
    execution.scrape_sources.create!(scrape_run: run, url: "https://example.com/good", position: 0)
    execution.scrape_sources.create!(scrape_run: run, url: "https://example.com/bad", position: 1)
    fetcher = FakeFetcher.new({
      "https://example.com/good" => "<html><title>First</title><main>First page</main></html>",
      "https://example.com/bad" => "HTTP 500"
    })

    Scraping::ProcessExecution.new(execution, fetcher:, llm_client: FakeLlmClient.new).call

    assert execution.reload.completed?
    assert_equal 1, execution.scrape_sources.where(status: "failed").count
    assert_equal 1, execution.combined_output.data["sources"].size
  end

  test "selector mode processes raw html without calling an llm" do
    project = Project.create!(name: "Links")
    rules = JSON.generate(item_selector: "a[href]", fields: { url: { value: "attribute", attribute: "href", resolve_url: true } })
    run = project.scrape_runs.create!(
      urls_text: "https://example.com/list", instructions: "Collect links", output_format: "json",
      output_schema: '{"items":[]}', processing_mode: "selectors", selector_rules: rules
    )
    execution = create_execution(run)
    execution.scrape_sources.create!(scrape_run: run, url: "https://example.com/list", position: 0)
    fetcher = FakeFetcher.new({ "https://example.com/list" => '<a href="/one">One</a><a href="/two">Two</a>' })

    Scraping::ProcessExecution.new(execution, fetcher:, llm_client: Object.new).call

    assert execution.reload.completed?
    output = execution.extraction_outputs.find_by!(kind: "source")
    assert_equal %w[https://example.com/one https://example.com/two], output.data.fetch("items").pluck("url")
    assert_equal 0, output.usage["llm_tokens"]
    assert_equal "Nokogiri selectors", output.model
  end

  test "reuses the prior source snapshot when the server returns not modified" do
    project = Project.create!(name: "Cached")
    run = project.scrape_runs.create!(
      urls_text: "https://example.com/item", instructions: "Collect title",
      output_format: "json", output_schema: '{"items":[]}'
    )
    previous_execution = create_execution(run)
    previous = previous_execution.scrape_sources.create!(
      scrape_run: run, url: "https://example.com/item", position: 0,
      status: "completed", final_url: "https://example.com/item", title: "Cached item",
      raw_html: "<main>Cached item</main>", extracted_text: "Cached item", structured_data: {},
      etag: '"item-v1"', content_digest: "digest-v1", fetched_at: 1.hour.ago
    )
    execution = create_execution(run)
    source = execution.scrape_sources.create!(scrape_run: run, url: previous.url, position: 0)
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) do |url, **options|
      raise "missing validator" unless options[:etag] == '"item-v1"'

      Scraping::PageFetcher::Result.new(url:, status: 304, etag: options[:etag])
    end

    Scraping::ProcessExecution.new(execution, fetcher:, llm_client: FakeLlmClient.new).call

    assert execution.reload.completed?
    assert source.reload.content_reused?
    assert_equal "<main>Cached item</main>", source.raw_html
    assert_equal "digest-v1", source.content_digest
  end

  private

  def create_execution(run)
    run.scrape_executions.create!(
      instructions: run.instructions,
      output_format: run.output_format,
      output_schema: run.output_schema,
      extraction_model: "test-model",
      processing_mode: run.processing_mode,
      selector_rules: run.selector_rules
    )
  end
end
