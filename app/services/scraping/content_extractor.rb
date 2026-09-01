require "nokogiri"

module Scraping
  class ContentExtractor
    Result = Data.define(:title, :text, :structured_data)
    REMOVED_SELECTORS = "script, style, noscript, svg, canvas, iframe, template, nav, footer".freeze
    MAX_TEXT_LENGTH = ENV.fetch("SCRAPER_MAX_TEXT_LENGTH", 80_000).to_i
    MAX_VALUE_LENGTH = 2_000
    SENSITIVE_KEY_PATTERN = /(?:csrf|authenticity|password|secret|access[_-]?token|api[_-]?key|nonce)/i

    def extract(html, base_url: nil)
      document = Nokogiri::HTML5(html)
      title = clean_text(document.at_css("title")&.text).presence
      structured_data = extract_structure(document, base_url:)
      description = structured_data.dig("metadata", "description").to_s

      document.css(REMOVED_SELECTORS).remove
      body = document.at_css("main, article, body") || document
      text = utf8(body.text).lines.map(&:squish).reject(&:blank?).join("\n")
      text = [ description, text ].reject(&:blank?).join("\n\n")

      Result.new(
        title:,
        text: text.truncate(MAX_TEXT_LENGTH, omission: "\n\n[Content truncated by ParserAI]"),
        structured_data:
      )
    rescue StandardError => e
      raise PageFetcher::FetchError, "HTML parsing failed: #{e.message}"
    end

    private

    def extract_structure(document, base_url:)
      {
        "metadata" => metadata(document, base_url:),
        "headings" => headings(document),
        "links" => links(document, base_url:),
        "images" => images(document, base_url:),
        "tables" => tables(document),
        "json_ld" => json_scripts(document, 'script[type="application/ld+json"]'),
        "embedded_json" => json_scripts(document, 'script[type="application/json"], script#__NEXT_DATA__'),
        "microdata" => microdata(document),
        "data_attributes" => data_attributes(document),
        "labeled_elements" => labeled_elements(document),
        "hidden_content" => hidden_content(document)
      }.compact_blank
    end

    def metadata(document, base_url:)
      named = {}
      document.css("meta[name], meta[property]").first(100).each do |node|
        key = node["property"].presence || node["name"].presence
        value = clean_value(node["content"])
        next if key.blank? || value.blank? || key.match?(SENSITIVE_KEY_PATTERN)

        named[key.downcase] = value
      end

      {
        "title" => clean_text(document.at_css("title")&.text),
        "description" => named["description"],
        "canonical_url" => absolute_url(document.at_css('link[rel~="canonical"]')&.[]("href"), base_url),
        "language" => document.at_css("html")&.[]("lang"),
        "open_graph" => named.select { |key, _| key.start_with?("og:") },
        "twitter" => named.select { |key, _| key.start_with?("twitter:") },
        "other" => named.reject { |key, _| key == "description" || key.start_with?("og:", "twitter:") }
      }.compact_blank
    end

    def headings(document)
      document.css("h1, h2, h3, h4, h5, h6").first(100).filter_map do |node|
        text = clean_text(node.text)
        { "level" => node.name.delete_prefix("h").to_i, "text" => text }.compact_blank if text.present?
      end
    end

    def links(document, base_url:)
      document.css("a[href], area[href]").first(300).filter_map do |node|
        href = clean_value(node["href"])
        next if href.blank? || href.start_with?("javascript:")

        {
          "text" => clean_text(node.text),
          "url" => absolute_url(href, base_url),
          "title" => clean_value(node["title"]),
          "rel" => clean_value(node["rel"]),
          "download" => node.key?("download") || nil
        }.compact_blank
      end.uniq
    end

    def images(document, base_url:)
      document.css("img, source[src], source[srcset]").first(200).filter_map do |node|
        src = node["src"].presence || node["data-src"].presence || node["data-lazy-src"].presence
        next if src.blank? && node["srcset"].blank?

        {
          "url" => absolute_url(src, base_url),
          "srcset" => clean_value(node["srcset"]),
          "alt" => clean_value(node["alt"]),
          "title" => clean_value(node["title"]),
          "width" => clean_value(node["width"]),
          "height" => clean_value(node["height"]),
          "loading" => clean_value(node["loading"])
        }.compact_blank
      end.uniq
    end

    def tables(document)
      document.css("table").first(20).map do |table|
        caption = clean_text(table.at_css("caption")&.text)
        rows = table.css("tr").first(50).map do |row|
          row.css("th, td").first(30).map { |cell| clean_text(cell.text) }
        end.reject(&:empty?)
        { "caption" => caption, "rows" => rows }.compact_blank
      end.reject { |table| table["rows"].blank? }
    end

    def json_scripts(document, selector)
      document.css(selector).first(30).filter_map do |node|
        content = utf8(node.text).strip
        next if content.blank? || content.bytesize > 250_000

        redact_sensitive(JSON.parse(content))
      rescue JSON::ParserError
        nil
      end
    end

    def microdata(document)
      document.css("[itemscope], [itemprop]").first(150).map do |node|
        {
          "tag" => node.name,
          "itemtype" => clean_value(node["itemtype"]),
          "itemprop" => clean_value(node["itemprop"]),
          "content" => clean_value(node["content"] || node["href"] || node["src"] || clean_text(node.text))
        }.compact_blank
      end
    end

    def data_attributes(document)
      document.css("*").filter_map do |node|
        attributes = node.attribute_nodes.select { |attribute| attribute.name.start_with?("data-") && !attribute.name.match?(SENSITIVE_KEY_PATTERN) }.to_h do |attribute|
          [ attribute.name, clean_value(attribute.value) ]
        end.compact_blank
        next if attributes.empty?

        { "tag" => node.name, "id" => node["id"], "text" => clean_text(node.text).truncate(300), "attributes" => attributes }.compact_blank
      end.first(150)
    end

    def labeled_elements(document)
      document.css("[aria-label], [aria-labelledby], [role]").first(150).map do |node|
        {
          "tag" => node.name,
          "role" => clean_value(node["role"]),
          "label" => clean_value(node["aria-label"]),
          "labelled_by" => clean_value(node["aria-labelledby"]),
          "text" => clean_text(node.text).truncate(300)
        }.compact_blank
      end
    end

    def hidden_content(document)
      document.css('[hidden], [aria-hidden="true"], input[type="hidden"], template').first(100).filter_map do |node|
        next if node["name"].to_s.match?(SENSITIVE_KEY_PATTERN)

        value = node["value"].presence || clean_text(node.text)
        next if value.blank?

        { "tag" => node.name, "name" => clean_value(node["name"]), "value" => clean_value(value) }.compact_blank
      end
    end

    def absolute_url(value, base_url)
      return if value.blank?
      return clean_value(value) if base_url.blank?

      URI.join(base_url, value).to_s
    rescue URI::InvalidURIError
      clean_value(value)
    end

    def clean_text(value)
      utf8(value).squish.truncate(MAX_VALUE_LENGTH)
    end

    def redact_sensitive(value)
      case value
      when Hash
        value.to_h { |key, item| [ key, key.to_s.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : redact_sensitive(item) ] }
      when Array
        value.map { |item| redact_sensitive(item) }
      else
        value
      end
    end

    def clean_value(value)
      utf8(value).strip.truncate(MAX_VALUE_LENGTH)
    end

    def utf8(value)
      string = value.to_s
      string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
    rescue Encoding::CompatibilityError
      string.dup.force_encoding(Encoding::BINARY).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
    end
  end
end
