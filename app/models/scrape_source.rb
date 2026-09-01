class ScrapeSource < ApplicationRecord
  has_many :llm_requests, dependent: :nullify
  STATUSES = %w[queued fetching fetched processing completed failed canceled].freeze

  belongs_to :scrape_run, inverse_of: :scrape_sources
  belongs_to :scrape_execution, inverse_of: :scrape_sources
  has_many :extraction_outputs, dependent: :destroy

  validates :url, presence: true
  validates :position, presence: true, uniqueness: { scope: :scrape_execution_id }
  validates :status, inclusion: { in: STATUSES }
  validate :url_is_http

  STATUSES.each { |value| define_method("#{value}?") { status == value } }

  def host
    URI.parse(final_url.presence || url).host
  rescue URI::InvalidURIError
    url
  end

  def source_output
    extraction_outputs.where(kind: "source", status: "completed").order(created_at: :desc).first
  end

  private

  def url_is_http
    uri = URI.parse(url.to_s)
    errors.add(:url, "must be a complete HTTP or HTTPS URL") unless %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "is not valid")
  end
end
