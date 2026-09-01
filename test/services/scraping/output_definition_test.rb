require "test_helper"

class Scraping::OutputDefinitionTest < ActiveSupport::TestCase
  test "accepts a JSON schema" do
    definition = Scraping::OutputDefinition.new(
      format: "json",
      specification: '{"type":"object","properties":{"name":{"type":"string"}}}'
    )

    assert definition.json?
    assert_equal "object", definition.parsed["type"]
  end

  test "parses and deduplicates CSV columns" do
    definition = Scraping::OutputDefinition.new(format: "csv", specification: "name, price\nurl, name")

    assert_equal %w[name price url], definition.csv_columns
  end

  test "rejects malformed JSON" do
    error = assert_raises(Scraping::OutputDefinition::InvalidDefinition) do
      Scraping::OutputDefinition.new(format: "json", specification: "{bad")
    end

    assert_match "not valid JSON", error.message
  end
end
