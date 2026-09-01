class ScrapeExecution < ApplicationRecord
  STATUSES = %w[queued fetching processing completed failed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze

  belongs_to :scrape_run, touch: true
  has_many :scrape_sources, -> { order(:position) }, dependent: :destroy, inverse_of: :scrape_execution
  has_many :extraction_outputs, dependent: :destroy
  has_many :llm_requests, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :instructions, :output_format, :output_schema, presence: true
  validates :content_strategy, inclusion: { in: ScrapeRun::CONTENT_STRATEGIES }
  validates :processing_mode, inclusion: { in: ScrapeRun::PROCESSING_MODES }
  validate :selector_rules_are_valid

  scope :recent_first, -> { order(created_at: :desc) }

  STATUSES.each { |value| define_method("#{value}?") { status == value } }

  def active?
    %w[queued fetching processing].include?(status)
  end

  def request_cancellation!
    with_lock do
      return unless active?

      if queued?
        update!(status: "canceled", cancel_requested_at: Time.current, completed_at: Time.current)
        scrape_sources.where(status: "queued").update_all(status: "canceled", updated_at: Time.current)
      else
        update!(cancel_requested_at: Time.current)
      end
    end
  end

  def cancellation_requested?
    cancel_requested_at.present?
  end

  def combined_output
    extraction_outputs.where(kind: "combined", status: "completed").order(created_at: :desc).first
  end

  def output_definition
    @output_definition ||= Scraping::OutputDefinition.new(format: output_format, specification: output_schema)
  end

  def content_strategy_label
    ScrapeRun::CONTENT_STRATEGY_LABELS.fetch(content_strategy)
  end

  def processing_mode_label
    processing_mode == "selectors" ? "Nokogiri selectors" : "LLM extraction"
  end

  def progress_percentage
    return 100 if completed?
    return 0 if queued?
    return 20 if fetching? && scrape_sources.none? { |source| source.fetched? || source.failed? }

    source_progress = scrape_sources.sum do |source|
      case source.status
      when "completed", "failed" then 1.0
      when "processing", "fetched" then 0.7
      else 0.1
      end
    end
    ((source_progress / [ scrape_sources.size, 1 ].max) * 90).round
  end
  private

  def selector_rules_are_valid
    return unless processing_mode == "selectors"

    Scraping::SelectorRuleSet.new(selector_rules)
  rescue Scraping::SelectorRuleSet::InvalidRules => e
    errors.add(:selector_rules, e.message)
  end
end
