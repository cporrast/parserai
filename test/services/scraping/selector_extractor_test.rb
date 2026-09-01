require "test_helper"

class Scraping::SelectorExtractorTest < ActiveSupport::TestCase
  HTML = <<~HTML
    <section class="card"><a href="/one"><span class="name"> One </span><img src="/one.jpg"><img src="/two.jpg"></a></section>
    <section class="card"><a href="https://other.test/two"><span class="name">Two</span></a></section>
  HTML

  test "extracts text, attributes, multiple values, and resolves relative URLs" do
    rules = {
      selector_type: "css", item_selector: ".card", output_key: "links",
      fields: {
        title: { selector: ".name", value: "text" },
        url: { selector: "a", value: "attribute", attribute: "href", resolve_url: true },
        images: { selector: "img", value: "attribute", attribute: "src", multiple: true, resolve_url: true }
      }
    }

    result = Scraping::SelectorExtractor.new(rules).extract(html: HTML, base_url: "https://example.com/list")

    assert_equal 2, result.matched_items
    assert_equal "One", result.data.dig("links", 0, "title")
    assert_equal "https://example.com/one", result.data.dig("links", 0, "url")
    assert_equal %w[https://example.com/one.jpg https://example.com/two.jpg], result.data.dig("links", 0, "images")
  end

  test "supports xpath and forces rows for csv" do
    rules = { selector_type: "xpath", item_selector: "//section", fields: { name: { selector: ".//span", value: "text" } } }
    result = Scraping::SelectorExtractor.new(rules).extract(html: HTML, base_url: "https://example.com", output_format: "csv")

    assert_equal %w[One Two], result.data.fetch("rows").pluck("name")
  end

  test "rejects arbitrary transforms" do
    error = assert_raises(Scraping::SelectorRuleSet::InvalidRules) do
      Scraping::SelectorExtractor.new(item_selector: "a", fields: { url: { transforms: [ "eval" ] } })
    end
    assert_includes error.message, "unsupported transforms"
  end

  test "rejects nested field rules that the extractor cannot execute" do
    error = assert_raises(Scraping::SelectorRuleSet::InvalidRules) do
      Scraping::SelectorExtractor.new(
        item_selector: ".card",
        fields: {
          product: {
            fields: { name: { selector: ".name", value: "text" } }
          }
        }
      )
    end

    assert_includes error.message, "field product has unsupported keys: fields"
  end

  test "builds a safe highlighted preview with field diagnostics" do
    html = <<~HTML
      <html><head><script>alert('no')</script></head><body onload="alert('no')">
        <form action="https://example.net/submit">
          <section class="card"><a href="/one"><span class="name">One</span><span class="name">Duplicate</span></a></section>
          <section class="card"><a href="/two">No name</a></section>
        </form>
      </body></html>
    HTML
    rules = {
      item_selector: ".card",
      fields: { name: { selector: ".name", value: "text" } }
    }

    result = Scraping::SelectorExtractor.new(rules).extract(
      html:, base_url: "https://example.com/products", preview: true
    )
    preview = Nokogiri::HTML5(result.preview_html)

    assert_equal 2, result.diagnostics.fetch("matched_items")
    assert_equal 1, result.diagnostics.dig("fields", "name", "missing_items")
    assert_equal 1, result.diagnostics.dig("fields", "name", "multiple_match_items")
    assert result.diagnostics.fetch("warnings").any? { |warning| warning.include?("only the first value") }
    assert_equal %w[0 1], preview.css("[data-parserai-item]").map { |node| node["data-parserai-item"] }
    assert_equal 2, preview.css('[data-parserai-field-indexes~="0"]').size
    assert_nil preview.at_css("script")
    assert_nil preview.at_css("form")
    assert_nil preview.at_css("body")["onload"]
    assert_nil preview.at_css("a")["href"]
    assert preview.at_css('meta[http-equiv="Content-Security-Policy"]')
  end

  test "retains zero and false transformed values" do
    html = '<div class="card"><span class="count">0</span><span class="available">no</span></div>'
    rules = {
      item_selector: ".card",
      fields: {
        count: { selector: ".count", transforms: [ "integer" ] },
        available: { selector: ".available", transforms: [ "boolean" ] }
      }
    }

    result = Scraping::SelectorExtractor.new(rules).extract(html:, base_url: "https://example.com")

    assert_equal 0, result.data.dig("items", 0, "count")
    assert_equal false, result.data.dig("items", 0, "available")
    assert_equal 1, result.diagnostics.fetch("emitted_records")
    assert_equal 0, result.diagnostics.dig("fields", "available", "missing_items")
  end

  test "validates selector syntax before extraction" do
    error = assert_raises(Scraping::SelectorRuleSet::InvalidRules) do
      Scraping::SelectorRuleSet.new(item_selector: "article[", fields: { title: {} })
    end

    assert_includes error.message, "item_selector is invalid"
  end

  test "warns when an xpath field escapes css item scoping" do
    rules = {
      selector_type: "css",
      item_selector: ".card",
      fields: {
        title: { selector_type: "xpath", selector: "//span", value: "text" }
      }
    }

    result = Scraping::SelectorExtractor.new(rules).extract(html: HTML, base_url: "https://example.com")

    assert result.diagnostics.fetch("warnings").any? { |warning| warning.include?("Start with .//") }
  end
end
