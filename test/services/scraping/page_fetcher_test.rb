require "test_helper"

class Scraping::PageFetcherTest < ActiveSupport::TestCase
  test "rejects localhost and private network targets" do
    fetcher = Scraping::PageFetcher.new

    assert_raises(Scraping::PageFetcher::FetchError) { fetcher.fetch("http://localhost/admin") }
    assert_raises(Scraping::PageFetcher::FetchError) { fetcher.fetch("http://127.0.0.1/private") }
    assert_raises(Scraping::PageFetcher::FetchError) { fetcher.fetch("file:///etc/passwd") }
  end
end
