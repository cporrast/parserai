module Llm
  class PromptBudget
    DEFAULT_MAX_CHARS = 120_000
    OMISSION = "\n[... prompt content omitted by ParserAI ...]\n".freeze

    def initialize(max_chars: ENV.fetch("LLM_MAX_PROMPT_CHARS", DEFAULT_MAX_CHARS).to_i)
      @max_chars = [ max_chars, 100 ].max
    end

    def apply(messages)
      normalized = messages.map { |message| message.deep_dup }
      contents = normalized.map { |message| message[:content] || message["content"] }
      return normalized if contents.sum { |content| content.to_s.length } <= @max_chars

      allocations = allocate(contents.map { |content| content.to_s.length })
      normalized.each_with_index do |message, index|
        key = message.key?(:content) ? :content : "content"
        message[key] = sample(message[key].to_s, allocations[index])
      end
      normalized
    end

    private

    def allocate(lengths)
      allocations = Array.new(lengths.size, 0)
      remaining_indexes = lengths.each_index.to_a
      remaining_budget = @max_chars

      until remaining_indexes.empty?
        share = remaining_budget / remaining_indexes.size
        completed, remaining_indexes = remaining_indexes.partition do |index|
          if lengths[index] <= share
            allocations[index] = lengths[index]
            remaining_budget -= lengths[index]
            true
          else
            false
          end
        end
        break if completed.empty?
      end

      remaining_indexes.each { |index| allocations[index] = remaining_budget / remaining_indexes.size }
      allocations
    end

    def sample(content, limit)
      return content if content.length <= limit
      return content.first(limit) if limit <= (OMISSION.length * 2) + 30

      segment = (limit - (OMISSION.length * 2)) / 3
      middle_start = (content.length - segment) / 2
      [ content.first(segment), content.slice(middle_start, segment), content.last(segment) ].join(OMISSION)
    end
  end
end
