module Chat
  class Responder
    MAX_CONTEXT_LENGTH = ENV.fetch("CHAT_MAX_CONTEXT_LENGTH", 50_000).to_i

    def initialize(project, client: Llm::Client.new)
      @project = project
      @client = client
    end

    def reply(up_to_message: nil, async_operation: nil)
      @up_to_message = up_to_message
      model = @project.effective_chat_model
      result = @client.chat(
        messages: messages, model:, temperature: 0.3,
        loggable: @project, purpose: "project_chat", async_operation:
      )
      @project.chat_messages.create!(
        role: "assistant",
        content: result.content,
        model: result.model,
        metadata: { usage: result.usage, reply_to_message_id: up_to_message&.id }
      )
    end

    private

    def messages
      [ { role: "system", content: system_context } ] + conversation
    end

    def conversation
      scope = @project.chat_messages.in_order
      scope = scope.where("id <= ?", @up_to_message.id) if @up_to_message
      scope.last(12).map do |message|
        { role: message.role, content: message.content }
      end
    end

    def system_context
      <<~PROMPT.strip
        You are the data analyst inside ParserAI. Answer questions about this project's scraped data and structures.
        Be concise, identify which source supports a claim, and say when the available data is insufficient.

        Project: #{@project.name}
        Description: #{@project.description.presence || "No description"}

        Latest completed run outputs:
        #{project_output_context}
      PROMPT
    end

    def project_output_context
      context = @project.scrape_runs.recent_first.filter_map do |run|
        output = run.combined_output
        next unless output

        "#{run.display_name}:\n#{JSON.pretty_generate(output.data)}"
      end.join("\n\n")
      context.truncate(MAX_CONTEXT_LENGTH, omission: "\n[Older data omitted]")
    end
  end
end
