require "digest"

module Scraping
  class ProcessExecution
    def initialize(execution, fetcher: PageFetcher.new, content_extractor: ContentExtractor.new, llm_client: nil)
      @execution = execution
      @run = execution.scrape_run
      @fetcher = fetcher
      @content_extractor = content_extractor
      @llm_client = llm_client
    end

    def call
      return if @execution.canceled?

      @execution.update!(status: "fetching", started_at: Time.current, completed_at: nil, error_message: nil)
      successful_outputs = []
      @execution.scrape_sources.each do |source|
        break if @execution.reload.cancellation_requested?

        output = process_source(source)
        successful_outputs << output if output
      end
      if @execution.cancellation_requested?
        cancel_execution
        return
      end
      raise "No pages were processed successfully" if successful_outputs.empty?

      create_combined_output(successful_outputs)
      @execution.update!(status: "completed", completed_at: Time.current)
    rescue StandardError => e
      @execution.update_columns(status: "failed", error_message: e.message.truncate(2_000), completed_at: Time.current, updated_at: Time.current)
      Rails.logger.error("Scrape execution #{@execution.id} failed: #{e.class}: #{e.message}")
    end

    private

    def cancel_execution
      @execution.scrape_sources.where(status: %w[queued fetching fetched processing])
        .update_all(status: "canceled", updated_at: Time.current)
      @execution.update!(status: "canceled", completed_at: Time.current)
    end

    def process_source(source)
      source.update!(status: "fetching", error_message: nil)
      previous = previous_source(source)
      page = @fetcher.fetch(
        previous&.final_url.presence || source.url,
        etag: previous&.etag,
        last_modified: previous&.last_modified
      )
      return process_reused_source(source, previous, page) if page.not_modified? && previous

      content = @content_extractor.extract(page.body, base_url: page.url)
      source.update!(
        status: "fetched",
        final_url: page.url,
        http_status: page.status,
        content_type: page.content_type,
        title: content.title,
        raw_html: page.body,
        extracted_text: content.text,
        structured_data: content.structured_data,
        etag: page.etag,
        last_modified: page.last_modified,
        content_digest: Digest::SHA256.hexdigest(page.body),
        content_reused: false,
        fetched_at: Time.current
      )

      @execution.update!(status: "processing") unless @execution.processing?
      source.update!(status: "processing")
      extract_source(source)
    rescue StandardError => e
      save_failed_output(source, e) if source.processing? || source.fetched?
      source.update_columns(status: "failed", error_message: e.message.truncate(2_000), updated_at: Time.current)
      nil
    end

    def process_reused_source(source, previous, page)
      source.update!(
        status: "fetched",
        final_url: previous.final_url,
        http_status: page.status,
        content_type: previous.content_type,
        title: previous.title,
        raw_html: previous.raw_html,
        extracted_text: previous.extracted_text,
        structured_data: previous.structured_data,
        etag: page.etag,
        last_modified: page.last_modified,
        content_digest: previous.content_digest,
        content_reused: true,
        fetched_at: Time.current
      )
      @execution.update!(status: "processing") unless @execution.processing?
      source.update!(status: "processing")
      extract_source(source)
    end

    def previous_source(source)
      @run.scrape_sources
        .where(url: source.url, status: "completed")
        .where.not(scrape_execution_id: @execution.id)
        .where.not(raw_html: nil)
        .order(fetched_at: :desc)
        .first
    end

    def extract_source(source)
      return extract_with_selectors(source) if @execution.processing_mode == "selectors"

      result = LlmExtractor.new(client: @llm_client || Llm::Client.new).extract(
        source:,
        instructions: @execution.instructions,
        definition: @execution.output_definition,
        model: @execution.extraction_model,
        content_strategy: @execution.content_strategy,
        loggable: @run,
        scrape_execution: @execution
      )

      output = @execution.extraction_outputs.create!(
        scrape_run: @run,
        scrape_source: source,
        kind: "source",
        status: "completed",
        model: result.model,
        prompt: result.prompt,
        raw_response: JSON.generate(result.raw_response),
        data: result.data,
        usage: result.usage,
        generated_at: Time.current
      )
      source.update!(status: "completed")
      output
    end

    def extract_with_selectors(source)
      result = SelectorExtractor.new(@execution.selector_rules).extract(
        html: source.raw_html,
        base_url: source.final_url.presence || source.url,
        output_format: @execution.output_format
      )
      output = @execution.extraction_outputs.create!(
        scrape_run: @run,
        scrape_source: source,
        kind: "source",
        status: "completed",
        model: "Nokogiri selectors",
        raw_response: JSON.generate(result.rules),
        data: result.data,
        usage: { "matched_items" => result.matched_items, "llm_tokens" => 0 },
        generated_at: Time.current
      )
      source.update!(status: "completed")
      output
    end

    def save_failed_output(source, error)
      result = error.respond_to?(:llm_result) ? error.llm_result : nil
      @execution.extraction_outputs.create!(
        scrape_run: @run,
        scrape_source: source,
        kind: "source",
        status: "failed",
        model: result&.model || (@execution.processing_mode == "selectors" ? "Nokogiri selectors" : @execution.extraction_model),
        raw_response: result ? JSON.generate(result.raw) : (@execution.processing_mode == "selectors" ? @execution.selector_rules : nil),
        usage: result&.usage,
        error_message: error.message.truncate(2_000),
        generated_at: Time.current
      )
    end

    def create_combined_output(outputs)
      data = if @execution.output_definition.csv?
        { "rows" => outputs.flat_map { |output| output.data.fetch("rows", []) } }
      else
        {
          "sources" => outputs.map do |output|
            { "url" => output.scrape_source.final_url.presence || output.scrape_source.url, "data" => output.data }
          end
        }
      end

      @execution.extraction_outputs.create!(
        scrape_run: @run,
        kind: "combined",
        status: "completed",
        model: "ParserAI merge",
        data:,
        usage: {},
        generated_at: Time.current
      )
    end
  end
end
