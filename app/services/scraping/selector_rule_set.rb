require "nokogiri"

module Scraping
  class SelectorRuleSet
    class InvalidRules < StandardError; end

    SELECTOR_TYPES = %w[css xpath].freeze
    VALUE_TYPES = %w[text html attribute].freeze
    TRANSFORMS = %w[strip squish downcase upcase integer float boolean].freeze
    TOP_LEVEL_KEYS = %w[selector_type item_selector output_key fields].freeze
    FIELD_KEYS = %w[
      selector selector_type value attribute multiple resolve_url transforms
    ].freeze

    attr_reader :rules

    def initialize(value)
      @rules = value.is_a?(Hash) ? value.deep_stringify_keys : JSON.parse(value.to_s)
      validate!
    rescue JSON::ParserError => e
      raise InvalidRules, "must be valid JSON: #{e.message}"
    end

    def selector_type
      rules.fetch("selector_type", "css")
    end

    def item_selector
      rules["item_selector"]
    end

    def output_key
      rules["output_key"].presence
    end

    def fields
      rules["fields"]
    end

    private

    def validate!
      raise InvalidRules, "must be a JSON object" unless rules.is_a?(Hash)
      raise InvalidRules, "has an unsupported selector_type" unless SELECTOR_TYPES.include?(selector_type)
      raise InvalidRules, "must include item_selector" if item_selector.blank?
      raise InvalidRules, "item_selector must be a string" unless item_selector.is_a?(String)
      validate_selector!(item_selector, selector_type, "item_selector")
      raise InvalidRules, "output_key must be a string" if rules.key?("output_key") && !rules["output_key"].is_a?(String)
      raise InvalidRules, "must include a fields object" unless fields.is_a?(Hash) && fields.any?
      raise InvalidRules, "supports at most 100 fields" if fields.size > 100
      reject_unknown_keys!(rules, TOP_LEVEL_KEYS, "top level")

      fields.each { |name, configuration| validate_field!(name, configuration) }
    end

    def validate_field!(name, configuration)
      raise InvalidRules, "field names can't be blank" if name.blank?
      raise InvalidRules, "field #{name} must be an object" unless configuration.is_a?(Hash)
      reject_unknown_keys!(configuration, FIELD_KEYS, "field #{name}")

      if configuration["selector"].present? && !configuration["selector"].is_a?(String)
        raise InvalidRules, "field #{name} selector must be a string"
      end

      field_selector_type = configuration["selector_type"].presence || selector_type
      validate_selector!(configuration["selector"], field_selector_type, "field #{name} selector") if configuration["selector"].present?

      value_type = configuration.fetch("value", "text")
      raise InvalidRules, "field #{name} has an unsupported value type" unless VALUE_TYPES.include?(value_type)
      if value_type == "attribute" && configuration["attribute"].blank?
        raise InvalidRules, "field #{name} must name an attribute"
      end
      if configuration["attribute"].present? && !configuration["attribute"].is_a?(String)
        raise InvalidRules, "field #{name} attribute must be a string"
      end
      if configuration["selector_type"].present? && !SELECTOR_TYPES.include?(configuration["selector_type"])
        raise InvalidRules, "field #{name} has an unsupported selector type"
      end

      transforms = Array(configuration["transforms"])
      unsupported = transforms - TRANSFORMS
      raise InvalidRules, "field #{name} has unsupported transforms: #{unsupported.join(", ")}" if unsupported.any?

      %w[multiple resolve_url].each do |option|
        next unless configuration.key?(option)
        next if [ true, false ].include?(configuration[option])

        raise InvalidRules, "field #{name} #{option} must be true or false"
      end
    end

    def reject_unknown_keys!(value, allowed_keys, location)
      unknown_keys = value.keys - allowed_keys
      return if unknown_keys.empty?

      raise InvalidRules, "#{location} has unsupported keys: #{unknown_keys.join(", ")}"
    end

    def validate_selector!(selector, type, location)
      raise InvalidRules, "#{location} is too long" if selector.length > 2_000

      if type == "xpath"
        Nokogiri::HTML5("<html><body></body></html>").xpath(selector)
      else
        Nokogiri::CSS.xpath_for(selector)
      end
    rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError => e
      raise InvalidRules, "#{location} is invalid: #{e.message}"
    end
  end
end
