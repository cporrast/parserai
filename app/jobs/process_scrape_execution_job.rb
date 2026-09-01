class ProcessScrapeExecutionJob < ApplicationJob
  queue_as :default

  def perform(scrape_execution)
    Scraping::ProcessExecution.new(scrape_execution).call
  end
end
