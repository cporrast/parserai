# Scraping services

Each service in this folder owns one part of a scraping workflow. Controllers create or invoke
workflows; these objects perform the scraping work.

## Workflow setup

1. A controller creates an `AsyncOperation`; Solid Queue runs the setup work while the browser polls
   the durable status record.
2. `SetupPageCache` fetches the first URL once and stores its raw HTML, readable text, and parsed
   structure in `SetupPageSnapshot`. Stale snapshots use ETag/Last-Modified revalidation, and
   unchanged content keeps its recommendation caches.
3. `SchemaRecommender` recommends only the output schema and caches it independently.
4. `SelectorRuleRecommender` recommends only executable selector rules. It tests the rules against
   the saved HTML and asks the model for one correction when validation fails or nothing matches.
5. `SelectorHtmlSample` removes scripts and irrelevant attributes before HTML is sent to the model.
6. `SelectorRuleSet` validates the supported JSON rule format.
7. `SelectorExtractor` executes validated rules and records match diagnostics. The same service
   powers setup previews and saved selector-mode executions.
8. `SelectorPreviewDocument` removes active content from the annotated Nokogiri document, installs
   a restrictive preview policy, and renders the highlighted HTML used by the sandboxed iframe.

## Saved executions

1. `StartExecution` snapshots a saved `ScrapeRun`, creates its sources, and enqueues the job.
2. `ProcessExecution` conditionally revalidates each source, reuses a prior HTML snapshot after a
   304 response, and chooses one extraction engine:
   - `LlmExtractor` interprets page content and returns schema-shaped JSON.
   - `SelectorExtractor` runs saved CSS or XPath rules without an LLM call.
3. `ProcessExecution` checks for cooperative cancellation between sources, stores each source
   result, and creates the combined export.

## Supporting services

- `PageFetcher` performs guarded public HTTP requests, conditional revalidation, and response
  encoding normalization.
- `ContentExtractor` converts HTML into readable text and safe structured page data.
- `OutputDefinition` validates JSON or CSV output requirements and builds the LLM instruction.
- `Schedule` calculates and advances recurring execution times.

Keep provider-specific transport and API auditing under `app/services/llm`. New scraping workflows
should reuse the fetcher, page cache, rule validator, and extractors instead of duplicating them.
