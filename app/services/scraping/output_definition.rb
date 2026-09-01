require "csv"

module Scraping
  class OutputDefinition
    class InvalidDefinition < StandardError; end

    attr_reader :format, :specification

    def initialize(format:, specification:)
      @format = format.to_s
      @specification = specification.to_s.strip
      validate!
    end

    def parsed
      @parsed ||= if json?
        JSON.parse(specification)
      else
        csv_columns
      end
    end

    def json?
      format == "json"
    end

    def csv?
      format == "csv"
    end

    def csv_columns
      @csv_columns ||= CSV.parse_line(specification.tr("\n", ","), skip_blanks: true)&.map(&:strip)&.reject(&:blank?)&.uniq || []
    rescue CSV::MalformedCSVError => e
      raise InvalidDefinition, "is not a valid CSV column layout: #{e.message}"
    end

    def prompt_description
      if json?
        "Return a JSON value matching this JSON Schema or example structure:\n#{JSON.pretty_generate(parsed)}"
      else
        <<~TEXT.strip
          Return a JSON object with a single `rows` array. Each row must be an object with exactly these columns:
          #{csv_columns.join(", ")}
        TEXT
      end
    end

    private

    def validate!
      raise InvalidDefinition, "can't be blank" if specification.blank?
      raise InvalidDefinition, "uses an unsupported format" unless %w[json csv].include?(format)

      if json?
        value = parsed
        raise InvalidDefinition, "must be a JSON object or array" unless value.is_a?(Hash) || value.is_a?(Array)
      elsif csv_columns.empty?
        raise InvalidDefinition, "must list at least one CSV column"
      end
    rescue JSON::ParserError => e
      raise InvalidDefinition, "is not valid JSON: #{e.message}"
    end
  end
end
