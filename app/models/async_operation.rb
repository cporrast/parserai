class AsyncOperation < ApplicationRecord
  KINDS = %w[
    setup_prefetch
    schema_recommendation
    selector_rule_recommendation
    project_chat
  ].freeze
  STATUSES = %w[queued running completed failed canceled].freeze
  ACTIVE_STATUSES = %w[queued running].freeze

  belongs_to :operable, polymorphic: true, touch: true
  has_many :llm_requests, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[operable_type operable_id kind] }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  after_create_commit :enqueue

  STATUSES.each { |value| define_method("#{value}?") { status == value } }

  def self.enqueue!(operable:, kind:, input:, idempotency_key: nil)
    idempotency_key = idempotency_key.presence || SecureRandom.uuid
    operation_scope = where(operable:, kind:)
    existing = operation_scope.find_by(idempotency_key:)
    return existing if existing

    create!(
      operable:,
      kind:,
      input: input.deep_stringify_keys,
      idempotency_key:
    )
  rescue ActiveRecord::RecordNotUnique
    operation_scope.find_by!(idempotency_key:)
  end

  def active?
    status.in?(ACTIVE_STATUSES)
  end

  def start!
    with_lock do
      return false if canceled?
      if cancel_requested_at.present?
        update!(status: "canceled", completed_at: Time.current)
        return false
      end

      update!(
        status: "running",
        started_at: started_at || Time.current,
        attempts: attempts + 1,
        error_class: nil,
        error_message: nil,
        completed_at: nil
      )
    end
    true
  end

  def complete!(payload)
    with_lock do
      if cancel_requested_at.present?
        update!(status: "canceled", completed_at: Time.current)
        return
      end

      update!(status: "completed", result: payload, completed_at: Time.current)
    end
  end

  def fail!(error)
    return cancel! if cancel_requested_at.present?

    update!(
      status: "failed",
      error_class: error.class.name,
      error_message: error.message.to_s.truncate(10_000),
      completed_at: Time.current
    )
  end

  def request_cancellation!
    with_lock do
      return unless active?

      update!(cancel_requested_at: Time.current)
      cancel! if queued?
    end
  end

  def cancel!
    update!(status: "canceled", completed_at: Time.current)
  end

  private

  def enqueue
    ProcessAsyncOperationJob.perform_later(self)
  end
end
