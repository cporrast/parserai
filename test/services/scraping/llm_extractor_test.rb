require "test_helper"

class Scraping::LlmExtractorTest < ActiveSupport::TestCase
  Source = Struct.new(:url, :final_url, :title, :extracted_text, :structured_data, :raw_html)

  FakeClient = Struct.new(:content) do
    def chat(model:, **)
      Llm::Client::Result.new(
        content:,
        raw: { "model" => model },
        usage: { "total_tokens" => 10 },
        model:
      )
    end
  end

  test "checks top-level JSON type and required keys" do
    source = sample_source
    definition = Scraping::OutputDefinition.new(
      format: "json",
      specification: '{"type":"object","required":["items"],"properties":{"items":{"type":"array"}}}'
    )
    extractor = Scraping::LlmExtractor.new(client: FakeClient.new('{"other":[]}'))

    error = assert_raises(Scraping::LlmExtractor::InvalidResponse) do
      extractor.extract(source:, instructions: "Extract items", definition:, model: "test-model")
    end

    assert_match "missing required fields: items", error.message
    assert_equal "test-model", error.llm_result.model
  end

  test "normalizes CSV rows to the requested columns" do
    source = sample_source
    definition = Scraping::OutputDefinition.new(format: "csv", specification: "name,price")
    extractor = Scraping::LlmExtractor.new(client: FakeClient.new('{"rows":[{"name":"Widget","price":12,"extra":true}]}'))

    result = extractor.extract(source:, instructions: "Extract", definition:, model: "test-model")

    assert_equal({ "name" => "Widget", "price" => 12 }, result.data["rows"].first)
  end

  test "standard strategy sends readable and structured page representations" do
    definition = Scraping::OutputDefinition.new(format: "json", specification: '{"title":"string"}')
    extractor = Scraping::LlmExtractor.new(client: FakeClient.new('{"title":"Widget"}'))

    result = extractor.extract(source: sample_source, instructions: "Extract", definition:, model: "test-model")

    assert_includes result.prompt, "READABLE PAGE TEXT"
    assert_includes result.prompt, "STRUCTURED HTML DATA"
    assert_includes result.prompt, "https://example.com/image.jpg"
  end

  test "raw HTML strategy uses markup instead of the reduced representation" do
    definition = Scraping::OutputDefinition.new(format: "json", specification: '{"title":"string"}')
    extractor = Scraping::LlmExtractor.new(client: FakeClient.new('{"title":"Widget"}'))

    result = extractor.extract(source: sample_source, instructions: "Extract", definition:, model: "test-model", content_strategy: "raw_html")

    assert_includes result.prompt, "RAW HTML"
    assert_includes result.prompt, '<img src="/image.jpg">'
    refute_includes result.prompt, "STRUCTURED HTML DATA"
  end

  private

  def sample_source
    Source.new(
      "https://example.com",
      nil,
      "Page",
      "Readable content",
      { "images" => [ { "url" => "https://example.com/image.jpg" } ] },
      '<html><img src="/image.jpg"></html>'
    )
  end
end
