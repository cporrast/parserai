module Scraping
  class StartExecution
    class AlreadyRunning < StandardError; end

    def self.call(scrape_run, trigger: "manual")
      new(scrape_run, trigger:).call
    end

    def initialize(scrape_run, trigger:)
      @scrape_run = scrape_run
      @trigger = trigger
    end

    def call
      execution = nil
      @scrape_run.with_lock do
        if @scrape_run.scrape_executions.where(status: ScrapeExecution::STATUSES.first(3)).exists?
          raise AlreadyRunning, "This workflow already has an active execution"
        end

        execution = @scrape_run.scrape_executions.create!(
          trigger: @trigger,
          status: "queued",
          instructions: @scrape_run.instructions,
          output_format: @scrape_run.output_format,
          output_schema: @scrape_run.output_schema,
          content_strategy: @scrape_run.content_strategy,
          processing_mode: @scrape_run.processing_mode,
          selector_rules: @scrape_run.selector_rules,
          extraction_model: @scrape_run.effective_extraction_model
        )
        @scrape_run.urls.each_with_index do |url, position|
          execution.scrape_sources.create!(scrape_run: @scrape_run, url:, position:)
        end
      end

      ProcessScrapeExecutionJob.perform_later(execution)
      execution
    end
  end
end
