require "nokogiri"

module Scraping
  class SelectorHtmlSample
    MAX_LENGTH = 60_000
    OMITTED_SECTION = "\n[... HTML omitted ...]\n".freeze
    REMOVED_ELEMENTS = "script, style, noscript, svg, canvas, iframe, template".freeze
    USEFUL_ATTRIBUTES = %w[
      id class href src srcset alt title value name content property itemprop itemtype
      role aria-label aria-labelledby
    ].freeze

    def initialize(html)
      @html = html.to_s
    end

    def to_s
      document = Nokogiri::HTML5(@html)
      document.css(REMOVED_ELEMENTS).remove
      root = document.at_css("body") || document
      remove_irrelevant_attributes(root)

      bounded_sample(root.inner_html.gsub(/>\s+</, "><"))
    rescue StandardError
      @html.truncate(MAX_LENGTH, omission: "\n[HTML sample truncated by ParserAI]")
    end

    private

    def remove_irrelevant_attributes(root)
      root.css("*").each do |element|
        element.attribute_nodes.each do |attribute|
          next if useful_attribute?(attribute.name)

          element.remove_attribute(attribute.name)
        end
      end
    end

    def useful_attribute?(name)
      USEFUL_ATTRIBUTES.include?(name) || name.start_with?("data-")
    end

    def bounded_sample(html)
      return html if html.length <= MAX_LENGTH

      segment_length = (MAX_LENGTH - (OMITTED_SECTION.length * 2)) / 3
      middle_start = (html.length - segment_length) / 2

      [
        html.first(segment_length),
        html.slice(middle_start, segment_length),
        html.last(segment_length)
      ].join(OMITTED_SECTION)
    end
  end
end
