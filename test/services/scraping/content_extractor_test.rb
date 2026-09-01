require "test_helper"

class Scraping::ContentExtractorTest < ActiveSupport::TestCase
  test "extracts readable text and removes page chrome" do
    html = <<~HTML
      <html><head><title> Example product </title><meta name="description" content="A useful item"></head>
      <body><nav>Menu links</nav><main><h1>Widget</h1><p>$12.00 and in stock</p><script>secret()</script></main></body></html>
    HTML

    result = Scraping::ContentExtractor.new.extract(html)

    assert_equal "Example product", result.title
    assert_includes result.text, "A useful item"
    assert_includes result.text, "Widget"
    refute_includes result.text, "Menu links"
    refute_includes result.text, "secret"
  end

  test "normalizes binary page text to valid UTF-8" do
    html = "<html><title>Caf\xE9</title><body><main>Cr\xE8me br\xFBl\xE9e</main></body></html>".b

    result = Scraping::ContentExtractor.new.extract(html)

    assert_equal Encoding::UTF_8, result.title.encoding
    assert result.title.valid_encoding?
    assert_equal Encoding::UTF_8, result.text.encoding
    assert result.text.valid_encoding?
  end

  test "extracts links, images, metadata, JSON-LD, and hidden values" do
    html = <<~HTML
      <html lang="en"><head>
        <link rel="canonical" href="/products/widget">
        <meta property="og:image" content="/social.jpg">
        <script type="application/ld+json">{"@type":"Product","name":"Widget"}</script>
        <script type="application/json">{"productId":42,"accessToken":"do-not-send"}</script>
      </head><body>
        <a href="/buy" title="Buy now">Buy</a>
        <img src="/widget.jpg" srcset="/widget-2x.jpg 2x" alt="Blue widget">
        <input type="hidden" name="sku" value="ABC-123">
        <input type="hidden" name="authenticity_token" value="do-not-send">
        <div data-product-id="42" aria-label="Product card">Widget</div>
      </body></html>
    HTML

    result = Scraping::ContentExtractor.new.extract(html, base_url: "https://example.com/catalog")
    data = result.structured_data

    assert_equal "https://example.com/products/widget", data.dig("metadata", "canonical_url")
    assert_equal "https://example.com/buy", data.dig("links", 0, "url")
    assert_equal "https://example.com/widget.jpg", data.dig("images", 0, "url")
    assert_equal "Product", data.dig("json_ld", 0, "@type")
    assert_equal "ABC-123", data.dig("hidden_content", 0, "value")
    assert_equal "42", data.dig("data_attributes", 0, "attributes", "data-product-id")
    assert_equal "Product card", data.dig("labeled_elements", 0, "label")
    assert_equal "[REDACTED]", data.dig("embedded_json", 0, "accessToken")
    refute_includes data.fetch("hidden_content").to_json, "do-not-send"
  end
end
