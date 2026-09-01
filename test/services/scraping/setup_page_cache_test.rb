require "test_helper"

class Scraping::SetupPageCacheTest < ActiveSupport::TestCase
  FakeFetcher = Struct.new(:calls) do
    def fetch(url, **)
      self.calls += 1
      Scraping::PageFetcher::Result.new(url:, status: 200, content_type: "text/html", body: "<title>Cached page</title><a href='/one'>One</a>")
    end
  end

  test "reuses a fresh Nokogiri page snapshot" do
    fetcher = FakeFetcher.new(0)
    cache = Scraping::SetupPageCache.new(fetcher:)

    first = cache.fetch("https://example.com/list")
    second = cache.fetch("https://example.com/list")

    assert_equal 1, fetcher.calls
    assert_equal first.id, second.id
    assert_equal "Cached page", second.title
    assert_includes second.structured_data.fetch("links").first.fetch("url"), "/one"
  end

  test "revalidates a stale page and preserves recommendations after a 304" do
    url = "https://example.com/list"
    html = "<title>Unchanged</title><main>Same content</main>"
    snapshot = SetupPageSnapshot.create!(
      url_digest: Digest::SHA256.hexdigest(url),
      url:,
      final_url: url,
      raw_html: html,
      extracted_text: "Same content",
      structured_data: {},
      fetched_at: 7.hours.ago,
      etag: '"version-1"',
      content_digest: Digest::SHA256.hexdigest(html),
      suggested_schema: '{"type":"object"}',
      schema_cache_key: "keep-me"
    )
    requests = []
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch) do |requested_url, **options|
      requests << [ requested_url, options ]
      Scraping::PageFetcher::Result.new(
        url: requested_url,
        status: 304,
        etag: options[:etag],
        last_modified: options[:last_modified]
      )
    end

    result = Scraping::SetupPageCache.new(fetcher:).fetch(url)

    assert_equal '"version-1"', requests.first.last.fetch(:etag)
    assert_equal html, result.raw_html
    assert_equal "keep-me", result.schema_cache_key
    assert_equal '{"type":"object"}', result.suggested_schema
    assert result.fetched_at > 1.minute.ago
  end
end
