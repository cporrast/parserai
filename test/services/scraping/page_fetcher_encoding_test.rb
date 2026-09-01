require "test_helper"

class Scraping::PageFetcherEncodingTest < ActiveSupport::TestCase
  test "uses the HTTP charset to convert fetched bytes to UTF-8" do
    fetcher = Scraping::PageFetcher.new
    body = "<html><body>Caf\xE9</body></html>".b

    normalized = fetcher.send(:normalize_body, body, "text/html; charset=iso-8859-1")

    assert_equal "<html><body>Café</body></html>", normalized
    assert_equal Encoding::UTF_8, normalized.encoding
    assert normalized.valid_encoding?
  end

  test "replaces malformed bytes when no charset is provided" do
    fetcher = Scraping::PageFetcher.new

    normalized = fetcher.send(:normalize_body, "hello\xFFworld".b, "text/html")

    assert_equal Encoding::UTF_8, normalized.encoding
    assert normalized.valid_encoding?
    assert_includes normalized, "�"
  end
end
