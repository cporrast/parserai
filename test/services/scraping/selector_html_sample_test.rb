require "test_helper"

class Scraping::SelectorHtmlSampleTest < ActiveSupport::TestCase
  test "removes noisy head content and keeps selector-relevant body markup" do
    html = <<~HTML
      <html>
        <head><script>#{"noise" * 20_000}</script></head>
        <body>
          <article class="product-card" style="color: red" onclick="track()">
            <a href="/one" data-product-id="1"><span class="name">One</span></a>
          </article>
        </body>
      </html>
    HTML

    sample = Scraping::SelectorHtmlSample.new(html).to_s

    assert_includes sample, 'class="product-card"'
    assert_includes sample, 'data-product-id="1"'
    assert_includes sample, 'href="/one"'
    refute_includes sample, "noise"
    refute_includes sample, "onclick"
    refute_includes sample, "style="
  end

  test "samples the beginning, middle, and end of a large body" do
    html = <<~HTML
      <body>
        <div id="first-marker">First</div>#{"a" * 50_000}
        <div id="middle-marker">Middle</div>#{"b" * 50_000}
        <div id="last-marker">Last</div>
      </body>
    HTML

    sample = Scraping::SelectorHtmlSample.new(html).to_s

    assert_operator sample.length, :<=, Scraping::SelectorHtmlSample::MAX_LENGTH
    assert_includes sample, "first-marker"
    assert_includes sample, "middle-marker"
    assert_includes sample, "last-marker"
    assert_includes sample, "HTML omitted"
  end
end
