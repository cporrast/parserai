module Scraping
  class Schedule
    def self.refresh!(scrape_run, from: Time.current, force: false)
      next_time = if scrape_run.scheduled?
        force || scrape_run.next_run_at.blank? ? calculate(scrape_run.recurrence, from:) : scrape_run.next_run_at
      end
      scrape_run.update_column(:next_run_at, next_time)
    end

    def self.advance!(scrape_run, from: Time.current)
      scrape_run.update_column(:next_run_at, scrape_run.scheduled? ? calculate(scrape_run.recurrence, from:) : nil)
    end

    def self.calculate(recurrence, from: Time.current)
      case recurrence
      when "hourly" then from + 1.hour
      when "daily" then from + 1.day
      when "weekly" then from + 1.week
      when "monthly" then from + 1.month
      end
    end
  end
end
