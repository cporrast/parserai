class ScrapeRunsController < ApplicationController
  before_action :set_project, only: %i[new create suggest_schema suggest_rules test_rules prefetch_setup]
  before_action :set_run, only: %i[show edit update execute]

  def new
    @scrape_run = @project.scrape_runs.new(
      output_format: "json",
      output_schema: default_schema,
      content_strategy: "standard",
      processing_mode: "llm",
      extraction_model: Llm::Configuration.model_for(:extraction),
      setup_model: Llm::Configuration.model_for(:setup),
      selector_rules: default_selector_rules,
      recurrence: "manual"
    )
  end

  def create
    @scrape_run = @project.scrape_runs.new(scrape_run_params)
    if @scrape_run.save
      Scraping::Schedule.refresh!(@scrape_run, force: true)
      redirect_to @scrape_run, notice: "Workflow saved as a draft. Run it whenever the configuration is ready."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @executions = @scrape_run.scrape_executions.includes(:scrape_sources, :extraction_outputs)
    @latest_execution = @executions.first
    @llm_requests = @scrape_run.llm_requests
      .select(:id, :purpose, :status, :model_requested, :duration_ms, :created_at, :scrape_source_id)
      .includes(:scrape_source).recent_first
    @llm_usage = Llm::UsageSummary.new(
      @scrape_run.llm_requests.select(:id, :status, :usage, :duration_ms, :model_requested, :model_returned)
    )
    @async_operations = @scrape_run.async_operations.recent_first.limit(20)
  end

  def edit
    @project = @scrape_run.project
  end

  def update
    @project = @scrape_run.project
    if @scrape_run.update(scrape_run_params)
      Scraping::Schedule.refresh!(@scrape_run, force: @scrape_run.saved_change_to_recurrence?)
      redirect_to @scrape_run, notice: "Workflow changes saved. Future executions will use this version."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def execute
    unless @scrape_run.processing_mode == "selectors" || llm_configured?
      redirect_to @scrape_run, alert: "Set OPENROUTER_API_KEY (or LLM_API_KEY) before running this workflow."
      return
    end

    execution = Scraping::StartExecution.call(@scrape_run)
    redirect_to execution, notice: "Execution queued with a snapshot of the current workflow configuration."
  rescue Scraping::StartExecution::AlreadyRunning => e
    redirect_to @scrape_run, alert: e.message
  end

  def suggest_schema
    recommendation = recommendation_params
    if recommendation[:instructions].blank?
      render json: { error: "Add at least one URL and extraction instructions first." }, status: :unprocessable_entity
      return
    end

    operation = enqueue_operation(kind: "schema_recommendation", input: recommendation)
    render_operation(operation)
  rescue Scraping::PageFetcher::FetchError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def suggest_rules
    recommendation = recommendation_params
    operation = enqueue_operation(kind: "selector_rule_recommendation", input: recommendation)
    render_operation(operation)
  rescue Scraping::PageFetcher::FetchError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def test_rules
    input = selector_test_params
    page = Scraping::SetupPageCache.new.fetch(input[:url], refresh: input[:refresh])
    final_url = page.final_url.presence || page.url
    result = Scraping::SelectorExtractor.new(input[:selector_rules]).extract(
      html: page.raw_html,
      base_url: final_url,
      output_format: input[:output_format],
      preview: true
    )
    final_data = if input[:output_format] == "csv"
      result.data
    else
      { "sources" => [ { "url" => final_url, "data" => result.data } ] }
    end
    render json: {
      data: result.data,
      final_data:,
      preview_text: preview_text(final_data, input),
      matched_items: result.matched_items,
      diagnostics: result.diagnostics,
      preview_html: result.preview_html,
      page: {
        title: page.title,
        url: final_url,
        fetched_at: page.fetched_at,
        refreshed: input[:refresh]
      }
    }
  rescue Scraping::PageFetcher::FetchError, Scraping::SelectorRuleSet::InvalidRules,
         Scraping::SelectorExtractor::ExtractionError, Scraping::OutputDefinition::InvalidDefinition => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def prefetch_setup
    url = params[:url].to_s.lines.map(&:strip).find(&:present?)
    raise Scraping::PageFetcher::FetchError, "Add at least one URL first." if url.blank?

    operation = enqueue_operation(kind: "setup_prefetch", input: { url: })
    render_operation(operation)
  rescue Scraping::PageFetcher::FetchError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_run
    @scrape_run = ScrapeRun.includes(:project).find(params[:id])
  end

  def scrape_run_params
    params.require(:scrape_run).permit(:urls_text, :instructions, :processing_mode, :selector_rules, :content_strategy, :output_format, :output_schema, :recurrence, :extraction_model, :setup_model)
  end

  def recommendation_params
    {
      url: first_url!,
      instructions: params[:instructions].to_s.strip,
      output_schema: params[:output_schema].to_s,
      model: params[:setup_model].presence || Llm::Configuration.model_for(:setup)
    }
  end

  def selector_test_params
    recommendation_params.merge(
      selector_rules: params[:selector_rules].to_s,
      output_format: params[:output_format].presence_in(%w[json csv]) || "json",
      refresh: ActiveModel::Type::Boolean.new.cast(params[:refresh])
    )
  end

  def first_url!
    url = params[:url].to_s.lines.map(&:strip).find(&:present?)
    raise Scraping::PageFetcher::FetchError, "Add at least one URL first." if url.blank?

    url
  end

  def preview_text(final_data, input)
    return JSON.pretty_generate(final_data) unless input[:output_format] == "csv"

    definition = Scraping::OutputDefinition.new(format: "csv", specification: input[:output_schema])
    CSV.generate(headers: true) do |csv|
      csv << definition.csv_columns
      final_data.fetch("rows", []).each do |row|
        csv << definition.csv_columns.map { |column| row[column] }
      end
    end
  end

  def recommendation_loggable
    @project.scrape_runs.find_by(id: params[:scrape_run_id]) || @project
  end

  def enqueue_operation(kind:, input:)
    AsyncOperation.enqueue!(
      operable: recommendation_loggable,
      kind:,
      input:,
      idempotency_key: request.headers["Idempotency-Key"]
    )
  end

  def render_operation(operation)
    render json: {
      operation_id: operation.id,
      status: operation.status,
      status_url: async_operation_path(operation)
    }, status: :accepted
  end

  def default_schema
    JSON.pretty_generate(
      type: "object",
      properties: {
        items: {
          type: "array",
          items: { type: "object", properties: { title: { type: "string" }, summary: { type: "string" } } }
        }
      },
      required: [ "items" ]
    )
  end

  def default_selector_rules
    JSON.pretty_generate(
      selector_type: "css",
      item_selector: "a[href]",
      output_key: "items",
      fields: {
        url: { value: "attribute", attribute: "href", resolve_url: true },
        text: { value: "text" }
      }
    )
  end
end
