class ScrapeExecutionsController < ApplicationController
  def show
    @execution = ScrapeExecution.includes(scrape_run: :project).find(params[:id])
    @scrape_run = @execution.scrape_run
    @sources = @execution.scrape_sources.includes(:extraction_outputs)
    @outputs = @execution.extraction_outputs.newest_first
  end

  def cancel
    execution = ScrapeExecution.find(params[:id])
    execution.request_cancellation!
    redirect_to execution, notice: "Cancellation requested. The current network request may finish before processing stops."
  end
end
