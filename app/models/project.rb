class Project < ApplicationRecord
  has_many :scrape_runs, dependent: :destroy
  has_many :chat_messages, dependent: :destroy
  has_many :llm_requests, as: :loggable, dependent: :destroy
  has_many :async_operations, as: :operable, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :chat_model, length: { maximum: 200 }, allow_blank: true

  scope :recent_first, -> { order(updated_at: :desc) }

  def completed_executions_count
    scrape_runs.sum { |workflow| workflow.scrape_executions.count(&:completed?) }
  end

  def effective_chat_model
    chat_model.presence || Llm::Configuration.model_for(:chat)
  end

  def all_llm_requests
    project_requests = LlmRequest.where(loggable: self)
    workflow_requests = LlmRequest.where(loggable: scrape_runs)
    project_requests.or(workflow_requests)
  end
end
