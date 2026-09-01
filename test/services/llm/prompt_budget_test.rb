require "test_helper"

class Llm::PromptBudgetTest < ActiveSupport::TestCase
  test "keeps short prompts unchanged" do
    messages = [ { role: "system", content: "Be concise" }, { role: "user", content: "Hello" } ]

    assert_equal messages, Llm::PromptBudget.new(max_chars: 1_000).apply(messages)
  end

  test "samples oversized messages while preserving the beginning middle and end" do
    content = "A" * 500 + "MIDDLE" + "Z" * 500
    messages = [ { role: "user", content: } ]

    result = Llm::PromptBudget.new(max_chars: 300).apply(messages).first.fetch(:content)

    assert result.length <= 300
    assert result.start_with?("A")
    assert_includes result, "MIDDLE"
    assert result.end_with?("Z")
    assert_includes result, "prompt content omitted"
    assert_equal content, messages.first.fetch(:content), "the caller's messages should not be mutated"
  end
end
