class ExtractionOutput < ApplicationRecord
  KINDS = %w[source combined].freeze
  STATUSES = %w[completed failed].freeze

  belongs_to :scrape_run
  belongs_to :scrape_execution
  belongs_to :scrape_source, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :successful, -> { where(status: "completed") }
  scope :newest_first, -> { order(created_at: :desc) }

  def combined?
    kind == "combined"
  end
end
