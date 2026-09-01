require "nokogiri"

module Scraping
  class SelectorExtractor
    class ExtractionError < StandardError; end

    Result = Data.define(:data, :rules, :matched_items, :diagnostics, :preview_html)
    FieldExtraction = Data.define(:value, :nodes)

    def initialize(rules)
      @rule_set = rules.is_a?(SelectorRuleSet) ? rules : SelectorRuleSet.new(rules)
    end

    def extract(html:, base_url:, output_format: "json", preview: false)
      document = Nokogiri::HTML5(html)
      items = select(document, @rule_set.item_selector, @rule_set.selector_type)
      diagnostics = build_diagnostics(items)
      records = items.each_with_index.filter_map do |item, item_index|
        annotate_item(item, item_index) if preview
        extract_record(item, item_index:, base_url:, diagnostics:, annotate: preview)
      end
      output_key = output_format == "csv" ? "rows" : (@rule_set.output_key || "items")
      finalize_diagnostics!(diagnostics, records)

      Result.new(
        data: { output_key => records },
        rules: @rule_set.rules,
        matched_items: items.size,
        diagnostics:,
        preview_html: preview ? SelectorPreviewDocument.new(document, base_url:, fields: diagnostics["fields"]).render : nil
      )
    rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError => e
      raise ExtractionError, "Invalid selector: #{e.message}"
    end

    private

    def extract_record(item, item_index:, base_url:, diagnostics:, annotate:)
      record = @rule_set.fields.each_with_index.to_h do |(name, configuration), field_index|
        extraction = extract_field(item, configuration, base_url:)
        update_field_diagnostics!(diagnostics["fields"][name], extraction, configuration)
        annotate_field(extraction.nodes, name, field_index, item_index) if annotate
        [ name, extraction.value ]
      end
      record unless record.values.all? { |value| missing_value?(value) }
    end

    def extract_field(item, configuration, base_url:)
      selector = configuration["selector"].presence
      selector_type = configuration["selector_type"].presence || @rule_set.selector_type
      nodes = selector ? select(item, selector, selector_type) : [ item ]
      values = nodes.map { |node| node_value(node, configuration, base_url:) }
      value = configuration["multiple"] ? values.reject { |candidate| missing_value?(candidate) } : values.first
      FieldExtraction.new(value:, nodes:)
    end

    def node_value(node, configuration, base_url:)
      value = case configuration.fetch("value", "text")
      when "html" then node.inner_html.to_s.strip
      when "attribute" then node[configuration["attribute"]].to_s.strip
      else node.text.to_s.squish
      end
      value = value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
      value = resolve_url(value, base_url) if configuration["resolve_url"]
      Array(configuration["transforms"]).reduce(value) { |memo, transform| apply_transform(memo, transform) }
    end

    def select(node, selector, selector_type)
      selector_type == "xpath" ? node.xpath(selector) : node.css(selector)
    end

    def resolve_url(value, base_url)
      return value if value.blank? || base_url.blank?

      URI.join(base_url, value).to_s
    rescue URI::InvalidURIError
      value
    end

    def apply_transform(value, transform)
      case transform
      when "strip" then value.to_s.strip
      when "squish" then value.to_s.squish
      when "downcase" then value.to_s.downcase
      when "upcase" then value.to_s.upcase
      when "integer" then Integer(value, exception: false)
      when "float" then Float(value, exception: false)
      when "boolean" then %w[true 1 yes available in-stock].include?(value.to_s.strip.downcase)
      else value
      end
    end

    def build_diagnostics(items)
      fields = @rule_set.fields.each_with_index.to_h do |(name, configuration), index|
        [ name, {
          "color" => SelectorPreviewDocument.field_color(index),
          "matched_items" => 0,
          "missing_items" => 0,
          "total_matches" => 0,
          "multiple_match_items" => 0,
          "multiple" => configuration["multiple"] == true
        } ]
      end

      {
        "matched_items" => items.size,
        "emitted_records" => 0,
        "empty_records" => 0,
        "fields" => fields,
        "warnings" => selector_warnings(items)
      }
    end

    def update_field_diagnostics!(field_diagnostics, extraction, configuration)
      field_diagnostics["total_matches"] += extraction.nodes.size
      field_diagnostics["multiple_match_items"] += 1 if extraction.nodes.size > 1
      if missing_value?(extraction.value)
        field_diagnostics["missing_items"] += 1
      else
        field_diagnostics["matched_items"] += 1
      end

      return unless extraction.nodes.size > 1 && configuration["multiple"] != true

      field_diagnostics["uses_first_match"] = true
    end

    def finalize_diagnostics!(diagnostics, records)
      diagnostics["emitted_records"] = records.size
      diagnostics["empty_records"] = diagnostics["matched_items"] - records.size
      warnings = diagnostics["warnings"]

      warnings << "The item selector did not match any elements." if diagnostics["matched_items"].zero?
      if diagnostics["empty_records"].positive?
        warnings << "#{diagnostics["empty_records"]} matched items produced no field values and were omitted."
      end

      diagnostics["fields"].each do |name, field|
        if field["missing_items"].positive?
          warnings << "Field #{name.inspect} is missing in #{field["missing_items"]} of #{diagnostics["matched_items"]} matched items."
        end
        if field["uses_first_match"]
          warnings << "Field #{name.inspect} matched multiple elements in #{field["multiple_match_items"]} items; only the first value was used."
        end
      end
    end

    def selector_warnings(items)
      warnings = []
      @rule_set.fields.each do |name, configuration|
        next unless (configuration["selector_type"].presence || @rule_set.selector_type) == "xpath"
        next unless configuration["selector"].to_s.start_with?("//")

        warnings << "Field #{name.inspect} uses an absolute XPath. Start with .// to keep it inside each item."
      end

      item_paths = items.index_by(&:path)
      nested_items = items.count { |item| item.ancestors.any? { |ancestor| item_paths.key?(ancestor.path) } }
      warnings << "The item selector produced nested matches, which can duplicate content." if nested_items.positive?
      warnings
    end

    def annotate_item(item, item_index)
      item["data-parserai-item"] = item_index.to_s
    end

    def annotate_field(nodes, name, field_index, item_index)
      nodes.each do |node|
        indexes = node["data-parserai-field-indexes"].to_s.split
        node["data-parserai-field-indexes"] = (indexes << field_index.to_s).uniq.join(" ")
        names = node["data-parserai-field-names"].to_s.split(" · ")
        node["data-parserai-field-names"] = (names << name).reject(&:blank?).uniq.join(" · ")
        node["data-parserai-record"] = item_index.to_s
      end
    end

    def missing_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
