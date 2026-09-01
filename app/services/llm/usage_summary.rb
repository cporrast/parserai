module Llm
  class UsageSummary
    attr_reader :request_count, :failed_count, :prompt_tokens, :completion_tokens,
      :total_tokens, :cost, :average_duration_ms, :models

    def initialize(requests)
      rows = requests.to_a
      @request_count = rows.size
      @failed_count = rows.count(&:failed?)
      @prompt_tokens = sum_usage(rows, "prompt_tokens")
      @completion_tokens = sum_usage(rows, "completion_tokens")
      @total_tokens = sum_usage(rows, "total_tokens")
      @cost = rows.sum(&:reported_cost)
      durations = rows.filter_map(&:duration_ms)
      @average_duration_ms = durations.any? ? (durations.sum.to_f / durations.size).round : nil
      @models = rows.group_by { |row| row.model_returned.presence || row.model_requested }
        .transform_values(&:size)
        .sort_by { |_, count| -count }
        .to_h
    end

    private

    def sum_usage(rows, key)
      rows.sum { |row| row.usage.to_h[key].to_i }
    end
  end
end
