require "csv"

class ExtractionOutputsController < ApplicationController
  before_action :set_output

  def show; end

  def export
    if output_definition.csv?
      send_data(csv_data, filename: filename("csv"), type: "text/csv")
    else
      send_data(JSON.pretty_generate(@output.data), filename: filename("json"), type: "application/json")
    end
  end

  private

  def set_output
    @output = ExtractionOutput.includes(scrape_run: :project).find(params[:id])
  end

  def csv_data
    definition = output_definition
    rows = @output.data.is_a?(Hash) ? @output.data.fetch("rows", []) : []
    CSV.generate(headers: true) do |csv|
      csv << definition.csv_columns
      rows.each { |row| csv << definition.csv_columns.map { |column| row[column] } }
    end
  end

  def filename(extension)
    project = @output.scrape_run.project.name.parameterize.presence || "parser-ai"
    "#{project}-workflow-#{@output.scrape_run_id}-execution-#{@output.scrape_execution_id}-#{@output.kind}.#{extension}"
  end

  def output_definition
    (@output.scrape_execution || @output.scrape_run).output_definition
  end
end
