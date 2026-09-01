class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update]

  def index
    @projects = Project.recent_first.includes(:scrape_runs)
  end

  def show
    @runs = @project.scrape_runs.recent_first.includes(scrape_executions: %i[scrape_sources extraction_outputs])
    @chat_messages = @project.chat_messages.in_order.last(30)
    @selected_operation = @project.async_operations.find_by(id: params[:operation_id])
    @async_operations = @project.async_operations.recent_first.limit(20)
    @llm_requests = @project.llm_requests
      .select(:id, :purpose, :status, :model_requested, :duration_ms, :created_at, :scrape_source_id)
      .includes(:scrape_source).recent_first
    @llm_usage = Llm::UsageSummary.new(
      @project.all_llm_requests.select(:id, :status, :usage, :duration_ms, :model_requested, :model_returned)
    )
  end

  def new
    @project = Project.new(chat_model: Llm::Configuration.model_for(:chat))
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      redirect_to @project, notice: "Project created. Add your first scraping run."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :chat_model)
  end
end
