class ChatMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :project, touch: true

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true

  scope :in_order, -> { order(:created_at) }
end
