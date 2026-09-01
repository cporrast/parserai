require "test_helper"

class Scraping::ScheduleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "sets and clears the next run time" do
    workflow = create_workflow(recurrence: "daily")
    now = Time.zone.parse("2026-08-31 09:00")

    Scraping::Schedule.refresh!(workflow, from: now, force: true)
    assert_equal now + 1.day, workflow.reload.next_run_at

    workflow.update!(recurrence: "manual")
    Scraping::Schedule.refresh!(workflow)
    assert_nil workflow.reload.next_run_at
  end

  test "dispatcher creates a scheduled execution and advances the schedule" do
    workflow = create_workflow(recurrence: "hourly")
    workflow.update_column(:next_run_at, 1.minute.ago)

    assert_enqueued_with(job: ProcessScrapeExecutionJob) do
      DispatchScheduledRunsJob.perform_now
    end

    execution = workflow.scrape_executions.last
    assert_equal "scheduled", execution.trigger
    assert_equal workflow.urls, execution.scrape_sources.order(:position).pluck(:url)
    assert_operator workflow.reload.next_run_at, :>, Time.current
  end

  private

  def create_workflow(recurrence:)
    Project.create!(name: "Scheduled").scrape_runs.create!(
      urls_text: "https://example.com",
      instructions: "Extract the title",
      output_format: "json",
      output_schema: '{"title":"string"}',
      recurrence:
    )
  end
end
