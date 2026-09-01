module AsyncOperations
  class Processor
    def initialize(operation)
      @operation = operation
      @input = operation.input.with_indifferent_access
    end

    def call
      case @operation.kind
      when "setup_prefetch" then prefetch_setup_page
      when "schema_recommendation" then recommend_schema
      when "selector_rule_recommendation" then recommend_selector_rules
      when "project_chat" then respond_to_chat
      else raise ArgumentError, "Unsupported async operation: #{@operation.kind}"
      end
    end

    private

    def prefetch_setup_page
      snapshot = Scraping::SetupPageCache.new.fetch(@input.fetch(:url))
      { cached: true, title: snapshot.title, fetched_at: snapshot.fetched_at }
    end

    def recommend_schema
      result = Scraping::SchemaRecommender.new.recommend(
        url: @input.fetch(:url),
        instructions: @input.fetch(:instructions),
        current_schema: @input[:output_schema],
        model: @input.fetch(:model),
        loggable: @operation.operable,
        async_operation: @operation
      )
      { schema: result.schema, cached: result.cached }
    end

    def recommend_selector_rules
      result = Scraping::SelectorRuleRecommender.new.recommend(
        url: @input.fetch(:url),
        instructions: @input[:instructions],
        output_schema: @input[:output_schema],
        model: @input.fetch(:model),
        loggable: @operation.operable,
        async_operation: @operation
      )
      { rules: result.rules, cached: result.cached, matched_items: result.matched_items }
    end

    def respond_to_chat
      message = @operation.operable.chat_messages.find(@input.fetch(:chat_message_id))
      reply = Chat::Responder.new(@operation.operable).reply(
        up_to_message: message,
        async_operation: @operation
      )
      { chat_message_id: reply.id }
    end
  end
end
