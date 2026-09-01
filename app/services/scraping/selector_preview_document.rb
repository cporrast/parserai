require "nokogiri"
require "uri"

module Scraping
  class SelectorPreviewDocument
    COLORS = %w[#4f46e5 #0891b2 #059669 #d97706 #e11d48 #7c3aed #0f766e #c2410c].freeze
    REMOVED_ELEMENTS = "script, noscript, iframe, frame, object, embed, portal, meta[http-equiv]".freeze
    DISABLED_ATTRIBUTES = %w[action formaction ping srcdoc].freeze

    def self.field_color(index)
      COLORS[index % COLORS.length]
    end

    def initialize(document, base_url:, fields:)
      @document = document
      @base_url = base_url
      @fields = fields
    end

    def render
      sanitize!
      install_preview_head!
      @document.to_html
    end

    private

    def sanitize!
      @document.css(REMOVED_ELEMENTS).remove
      @document.css("form").each do |form|
        form.name = "div"
        form["data-parserai-disabled-form"] = "true"
      end
      @document.css("*").each do |node|
        node.attribute_nodes.each do |attribute|
          node.remove_attribute(attribute.name) if attribute.name.downcase.start_with?("on")
        end
        DISABLED_ATTRIBUTES.each { |attribute| node.remove_attribute(attribute) }
        node.remove_attribute("href") if node.name.in?(%w[a area])
      end
      @document.css("link").each do |link|
        link.remove unless link["rel"].to_s.split.include?("stylesheet")
      end
    end

    def install_preview_head!
      head = @document.at_css("head") || begin
        node = Nokogiri::XML::Node.new("head", @document)
        @document.at_css("html")&.children&.first&.add_previous_sibling(node)
        node
      end
      head.prepend_child(base_element) if safe_base_url?
      head.prepend_child(csp_element)
      head.add_child(style_element)
    end

    def safe_base_url?
      URI.parse(@base_url.to_s).scheme.in?(%w[http https])
    rescue URI::InvalidURIError
      false
    end

    def base_element
      node = Nokogiri::XML::Node.new("base", @document)
      node["href"] = @base_url
      node
    end

    def csp_element
      node = Nokogiri::XML::Node.new("meta", @document)
      node["http-equiv"] = "Content-Security-Policy"
      node["content"] = "default-src 'none'; img-src http: https: data:; style-src 'unsafe-inline' http: https:; font-src http: https: data:; media-src http: https: data:"
      node
    end

    def style_element
      node = Nokogiri::XML::Node.new("style", @document)
      node["data-parserai-preview"] = "true"
      node.content = preview_css
      node
    end

    def preview_css
      field_rules = @fields.each_with_index.map do |(_name, field), index|
        <<~CSS
          [data-parserai-field-indexes~="#{index}"] {
            outline: 3px solid #{field.fetch("color")} !important;
            outline-offset: 1px !important;
          }
        CSS
      end.join("\n")

      <<~CSS
        html { scroll-behavior: auto !important; }
        [data-parserai-item] {
          box-shadow: inset 0 0 0 2px rgba(79, 70, 229, .38) !important;
          background-image: linear-gradient(rgba(79, 70, 229, .05), rgba(79, 70, 229, .05)) !important;
        }
        [data-parserai-field-indexes] { position: relative !important; }
        a, button, input, select, textarea, [role="button"] { pointer-events: none !important; }
        #{field_rules}
      CSS
    end
  end
end
