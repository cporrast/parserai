class ScrapeRun < ApplicationRecord
  OUTPUT_FORMATS = %w[json csv].freeze
  RECURRENCES = %w[manual hourly daily weekly monthly].freeze
  CONTENT_STRATEGIES = %w[standard visible_text metadata raw_html].freeze
  PROCESSING_MODES = %w[llm selectors].freeze
  CONTENT_STRATEGY_LABELS = {
    "standard" => "Standard · text + structured HTML",
    "visible_text" => "Visible text only",
    "metadata" => "Metadata, links, and media",
    "raw_html" => "Raw HTML"
  }.freeze

  belongs_to :project, touch: true
  has_many :scrape_executions, -> { recent_first }, dependent: :destroy
  has_many :scrape_sources, dependent: :destroy
  has_many :extraction_outputs, dependent: :destroy
  has_many :llm_requests, as: :loggable, dependent: :destroy
  has_many :async_operations, as: :operable, dependent: :destroy

  validates :urls_text, presence: true
  validates :instructions, presence: true
  validates :output_schema, presence: true
  validates :output_format, inclusion: { in: OUTPUT_FORMATS }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :content_strategy, inclusion: { in: CONTENT_STRATEGIES }
  validates :processing_mode, inclusion: { in: PROCESSING_MODES }
  validates :extraction_model, :setup_model, length: { maximum: 200 }, allow_blank: true
  validate :urls_are_valid
  validate :output_schema_is_valid
  validate :selector_rules_are_valid

  scope :recent_first, -> { order(created_at: :desc) }

  def display_name
    "Workflow ##{id} · #{instructions.to_s.squish.truncate(50)}"
  end

  def active?
    latest_execution&.active? || false
  end

  def task_status
    latest_execution&.status || "draft"
  end

  def status_rank
    %w[queued fetching processing draft completed failed].index(task_status) || 99
  end

  def combined_output
    latest_completed_execution&.combined_output
  end

  def latest_execution
    scrape_executions.first
  end

  def latest_completed_execution
    scrape_executions.where(status: "completed").first
  end

  def urls
    urls_text.to_s.lines.map(&:strip).reject(&:blank?).uniq
  end

  def scheduled?
    recurrence != "manual"
  end

  def schedule_label
    {
      "manual" => "Manual only",
      "hourly" => "Every hour",
      "daily" => "Every day",
      "weekly" => "Every week",
      "monthly" => "Every month"
    }.fetch(recurrence)
  end

  def content_strategy_label
    CONTENT_STRATEGY_LABELS.fetch(content_strategy)
  end

  def processing_mode_label
    processing_mode == "selectors" ? "Nokogiri selectors" : "LLM extraction"
  end

  def effective_extraction_model
    extraction_model.presence || Llm::Configuration.model_for(:extraction)
  end

  def effective_setup_model
    setup_model.presence || Llm::Configuration.model_for(:setup)
  end

  def output_definition
    @output_definition ||= Scraping::OutputDefinition.new(format: output_format, specification: output_schema)
  end

  private

  def urls_are_valid
    errors.add(:urls_text, "must include at least one URL") if urls.empty?
    urls.each do |value|
      uri = URI.parse(value)
      unless %w[http https].include?(uri.scheme) && uri.host.present?
        errors.add(:urls_text, "contains an invalid URL: #{value}")
      end
    rescue URI::InvalidURIError
      errors.add(:urls_text, "contains an invalid URL: #{value}")
    end
  end

  def output_schema_is_valid
    output_definition
  rescue Scraping::OutputDefinition::InvalidDefinition => e
    errors.add(:output_schema, e.message)
  end

  def selector_rules_are_valid
    return unless processing_mode == "selectors"

    Scraping::SelectorRuleSet.new(selector_rules)
  rescue Scraping::SelectorRuleSet::InvalidRules => e
    errors.add(:selector_rules, e.message)
  end
end
