class LlmRequest < ApplicationRecord
  STATUSES = %w[pending completed failed].freeze

  belongs_to :loggable, polymorphic: true
  belongs_to :scrape_execution, optional: true
  belongs_to :scrape_source, optional: true
  belongs_to :async_operation, optional: true

  validates :purpose, :provider, :endpoint, :model_requested, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def display_purpose
    purpose.humanize
  end

  def reported_cost
    value = usage.to_h["cost"]
    value ||= response_payload.to_h.dig("usage", "cost") if has_attribute?(:response_payload)
    Float(value || 0)
  rescue ArgumentError, TypeError
    0.0
  end
end
