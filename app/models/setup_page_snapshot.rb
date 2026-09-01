class SetupPageSnapshot < ApplicationRecord
  validates :url_digest, :url, presence: true
  validates :url_digest, uniqueness: true

  def fresh?
    fetched_at.present? && fetched_at > 6.hours.ago && raw_html.present?
  end
end
