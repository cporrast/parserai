require "test_helper"

class Scraping::SchemaRecommenderTest < ActiveSupport::TestCase
  FakePageCache = Struct.new(:page) do
    def fetch(_url)
      page
    end
  end

  class CountingClient
    attr_reader :calls

    def initialize(schema)
      @schema = schema
      @calls = []
    end

    def chat(**arguments)
      @calls << arguments
      Llm::Client::Result.new(
        content: JSON.generate(@schema), raw: {}, usage: {}, model: arguments[:model]
      )
    end
  end

  test "recommends and caches a schema independently from selector rules" do
    page = create_page
    schema = {
      "type" => "object",
      "properties" => { "price" => { "type" => "number" } },
      "required" => [ "price" ]
    }
    client = CountingClient.new(schema)
    recommender = Scraping::SchemaRecommender.new(
      page_cache: FakePageCache.new(page), client:
    )

    first = recommender.recommend(
      url: page.url, instructions: "Extract the price", current_schema: "",
      model: "test/schema"
    )
    second = recommender.recommend(
      url: page.url, instructions: "Extract the price", current_schema: "",
      model: "test/schema"
    )

    assert_equal 1, client.calls.size
    assert_not first.cached
    assert second.cached
    assert_equal schema, JSON.parse(first.schema)
    assert_equal first.schema, second.schema
    assert page.reload.schema_generated_at.present?
    assert_nil page.suggested_rules
    assert_equal "schema_recommendation", client.calls.first[:purpose]
  end

  private

  def create_page
    SetupPageSnapshot.create!(
      url_digest: SecureRandom.hex(32), url: "https://example.com/product",
      final_url: "https://example.com/product", title: "Product",
      raw_html: "<main>Widget — $12</main>", extracted_text: "Widget — $12",
      structured_data: {}, fetched_at: Time.current
    )
  end
end
