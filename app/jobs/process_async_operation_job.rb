class ProcessAsyncOperationJob < ApplicationJob
  queue_as :default

  retry_on Scraping::PageFetcher::FetchError, Llm::Client::ResponseError,
    wait: :polynomially_longer, attempts: 3 do |job, error|
      operation = job.arguments.first
      operation.fail!(error) if operation&.active?
    end

  def perform(operation)
    return unless operation.start!

    result = AsyncOperations::Processor.new(operation).call
    operation.complete!(result)
  rescue Scraping::InvalidRecommendation, Llm::Client::ConfigurationError,
         ActiveRecord::RecordNotFound, ArgumentError => e
    operation.fail!(e) if operation.active?
  rescue Scraping::PageFetcher::FetchError, Llm::Client::ResponseError
    raise
  rescue StandardError => e
    operation.fail!(e) if operation.active?
    raise
  end
end
