class LlmRequestsController < ApplicationController
  def show
    @llm_request = LlmRequest.find(params[:id])
  end
end
