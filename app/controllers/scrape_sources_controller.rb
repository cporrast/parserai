class ScrapeSourcesController < ApplicationController
  def show
    @source = ScrapeSource.includes(scrape_run: :project).find(params[:id])
    @run = @source.scrape_run
    @execution = @source.scrape_execution
  end
end
