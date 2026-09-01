class ChatMessagesController < ApplicationController
  def create
    @project = Project.find(params[:project_id])
    content = chat_message_params[:content].to_s.strip
    if content.blank?
      redirect_to project_path(@project, anchor: "chat"), alert: "Enter a question first."
      return
    end

    operation = nil
    @project.transaction do
      message = @project.chat_messages.create!(role: "user", content:)
      operation = AsyncOperation.enqueue!(
        operable: @project,
        kind: "project_chat",
        input: { chat_message_id: message.id },
        idempotency_key: request.headers["Idempotency-Key"].presence || params[:idempotency_key]
      )
    end
    redirect_to project_path(@project, operation_id: operation.id, anchor: "chat"),
      notice: "Question queued. The answer will appear here when it is ready."
  end

  private

  def chat_message_params
    params.require(:chat_message).permit(:content)
  end
end
