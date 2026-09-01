class DispatchScheduledRunsJob < ApplicationJob
  queue_as :default

  def perform
    ScrapeRun.where.not(recurrence: "manual").where(next_run_at: ..Time.current).find_each do |scrape_run|
      dispatch(scrape_run)
    end
  end

  private

  def dispatch(scrape_run)
    Scraping::StartExecution.call(scrape_run, trigger: "scheduled")
  rescue Scraping::StartExecution::AlreadyRunning
    nil
  ensure
    Scraping::Schedule.advance!(scrape_run)
  end
end
