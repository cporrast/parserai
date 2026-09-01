require "test_helper"

class Scraping::SelectorRuleRecommenderTest < ActiveSupport::TestCase
  FakePageCache = Struct.new(:page) do
    def fetch(_url)
      page
    end
  end

  class SequenceClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def chat(**arguments)
      @calls << arguments
      content = @responses.fetch(@calls.length - 1)
      Llm::Client::Result.new(content:, raw: {}, usage: {}, model: arguments[:model])
    end
  end

  test "repairs an invalid nested response and caches rules that match the real page" do
    page = create_page
    invalid_nested_rules = JSON.generate(
      selector_rules: {
        products: {
          item_selector: ".product-card",
          fields: { name: { selector: ".name", value: "text" } }
        }
      }
    )
    valid_rules = JSON.generate(
      selector_type: "css", item_selector: ".product-card", output_key: "products",
      fields: {
        name: { selector: ".name", value: "text" },
        url: { selector: "a", value: "attribute", attribute: "href", resolve_url: true }
      }
    )
    client = SequenceClient.new(invalid_nested_rules, valid_rules)
    recommender = Scraping::SelectorRuleRecommender.new(
      page_cache: FakePageCache.new(page), client:
    )

    first = recommend(recommender, page)
    second = recommend(recommender, page)

    assert_equal 2, client.calls.size
    assert_not first.cached
    assert second.cached
    assert_equal 2, first.matched_items
    assert_equal ".product-card", JSON.parse(first.rules)["item_selector"]
    assert_includes client.calls.second[:messages].last[:content], "cannot be executed"
    assert_equal "selector_rule_recommendation", client.calls.first[:purpose]
    assert page.reload.selector_rules_generated_at.present?
    assert_nil page.suggested_schema
  end

  test "rejects recommendations that still do not match after correction" do
    page = create_page
    zero_match_rules = JSON.generate(
      selector_type: "css", item_selector: ".invented-class", output_key: "products",
      fields: { name: { selector: ".name", value: "text" } }
    )
    client = SequenceClient.new(zero_match_rules, zero_match_rules)
    recommender = Scraping::SelectorRuleRecommender.new(
      page_cache: FakePageCache.new(page), client:
    )

    error = assert_raises(Scraping::InvalidRecommendation) do
      recommend(recommender, page)
    end

    assert_equal 2, client.calls.size
    assert_includes error.message, "did not match any elements"
    assert_nil page.reload.suggested_rules
  end

  private

  def recommend(recommender, page)
    recommender.recommend(
      url: page.url, instructions: "Collect product names and URLs",
      output_schema: '{"products":[]}', model: "test/selectors"
    )
  end

  def create_page
    SetupPageSnapshot.create!(
      url_digest: SecureRandom.hex(32), url: "https://example.com/products",
      final_url: "https://example.com/products", fetched_at: Time.current,
      raw_html: <<~HTML,
        <html><head><script>#{"noise" * 10_000}</script></head><body>
          <article class="product-card"><a href="/one"><span class="name">One</span></a></article>
          <article class="product-card"><a href="/two"><span class="name">Two</span></a></article>
        </body></html>
      HTML
      extracted_text: "One\nTwo", structured_data: {}
    )
  end
end
