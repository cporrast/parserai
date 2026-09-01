class TasksController < ApplicationController
  SORT_COLUMNS = %w[project status updated].freeze
  DIRECTIONS = %w[asc desc].freeze

  def index
    @projects = Project.order(:name)
    @project_filter = params[:project_id].presence
    @status_filter = params[:status].presence
    @sort = SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "default"
    @direction = DIRECTIONS.include?(params[:direction]) ? params[:direction] : default_direction
    @tasks = filtered_tasks
  end

  private

  def filtered_tasks
    tasks = ScrapeRun.includes(:project, :scrape_executions).to_a
    tasks.select! { |task| task.project_id == @project_filter.to_i } if @project_filter
    tasks.select! { |task| task.task_status == @status_filter } if @status_filter
    sort_tasks(tasks)
  end

  def sort_tasks(tasks)
    return tasks.sort_by { |task| [ task.active? ? 0 : 1, -task.updated_at.to_f ] } if @sort == "default"

    sorted = case @sort
    when "project"
      tasks.sort_by { |task| [ task.project.name.downcase, task.instructions.downcase ] }
    when "status"
      tasks.sort_by { |task| [ task.status_rank, -task.updated_at.to_f ] }
    when "updated"
      tasks.sort_by(&:updated_at)
    end
    @direction == "desc" ? sorted.reverse : sorted
  end

  def default_direction
    params[:sort] == "updated" ? "desc" : "asc"
  end
end
