require "test_helper"

class TasksIndexTest < ActionDispatch::IntegrationTest
  test "default view places active workflows before newer inactive workflows" do
    active = create_workflow(name: "Active Project", instructions: "Currently fetching", updated_at: 2.days.ago)
    create_execution(active, status: "fetching")
    inactive = create_workflow(name: "Recent Project", instructions: "Recently completed", updated_at: 1.hour.ago)
    create_execution(inactive, status: "completed")

    get root_path

    assert_response :success
    assert_operator response.body.index("Currently fetching"), :<, response.body.index("Recently completed")
  end

  test "filters tasks by project and status" do
    first = create_workflow(name: "Catalog", instructions: "Catalog task")
    create_execution(first, status: "completed")
    second = create_workflow(name: "News", instructions: "News task")
    create_execution(second, status: "failed")

    get tasks_path(project_id: first.project_id)
    assert_includes response.body, "Catalog task"
    refute_includes response.body, "News task"

    get tasks_path(status: "failed")
    assert_includes response.body, "News task"
    refute_includes response.body, "Catalog task"
  end

  test "sorts by updated date in either direction" do
    older = create_workflow(name: "Older", instructions: "Older task", updated_at: 2.days.ago)
    newer = create_workflow(name: "Newer", instructions: "Newer task", updated_at: 1.hour.ago)

    get tasks_path(sort: "updated", direction: "asc")
    assert_operator response.body.index(older.instructions), :<, response.body.index(newer.instructions)

    get tasks_path(sort: "updated", direction: "desc")
    assert_operator response.body.index(newer.instructions), :<, response.body.index(older.instructions)
  end

  private

  def create_workflow(name:, instructions:, updated_at: Time.current)
    workflow = Project.create!(name:).scrape_runs.create!(
      urls_text: "https://example.com",
      instructions:,
      output_format: "json",
      output_schema: '{"title":"string"}',
      recurrence: "manual"
    )
    workflow.update_column(:updated_at, updated_at)
    workflow
  end

  def create_execution(workflow, status:)
    execution = workflow.scrape_executions.create!(
      status:,
      instructions: workflow.instructions,
      output_format: workflow.output_format,
      output_schema: workflow.output_schema,
      extraction_model: "test-model"
    )
    workflow.update_column(:updated_at, 2.days.ago) if status == "fetching"
    execution
  end
end
