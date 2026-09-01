class AsyncOperationsController < ApplicationController
  before_action :set_operation

  def show
    render json: {
      id: @operation.id,
      kind: @operation.kind,
      status: @operation.status,
      result: @operation.result,
      error: @operation.error_message,
      attempts: @operation.attempts
    }
  end

  def destroy
    @operation.request_cancellation!
    respond_to do |format|
      format.json { render json: { id: @operation.id, status: @operation.reload.status }, status: :accepted }
      format.html { redirect_back fallback_location: tasks_path, notice: "Cancellation requested." }
    end
  end

  private

  def set_operation
    @operation = AsyncOperation.find(params[:id])
  end
end
