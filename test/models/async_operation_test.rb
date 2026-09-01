require "test_helper"

class AsyncOperationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues once for the same idempotency key" do
    project = Project.create!(name: "Operations")

    assert_enqueued_jobs 1, only: ProcessAsyncOperationJob do
      first = AsyncOperation.enqueue!(
        operable: project,
        kind: "setup_prefetch",
        input: { url: "https://example.com" },
        idempotency_key: "same-request"
      )
      second = AsyncOperation.enqueue!(
        operable: project,
        kind: "setup_prefetch",
        input: { url: "https://example.com" },
        idempotency_key: "same-request"
      )

      assert_equal first, second
    end
  end

  test "a queued operation can be canceled before its job starts" do
    project = Project.create!(name: "Cancellation")
    operation = AsyncOperation.enqueue!(
      operable: project,
      kind: "setup_prefetch",
      input: { url: "https://example.com" }
    )

    operation.request_cancellation!

    assert operation.reload.canceled?
    assert operation.completed_at.present?
  end

  test "a retry finalizes cancellation requested while an operation was running" do
    project = Project.create!(name: "Running cancellation")
    operation = AsyncOperation.enqueue!(
      operable: project,
      kind: "setup_prefetch",
      input: { url: "https://example.com" }
    )
    assert operation.start!

    operation.request_cancellation!

    refute operation.start!
    assert operation.reload.canceled?
  end
end
