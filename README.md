# ParserAI

ParserAI is a personal extraction studio for turning public web pages into structured data. A project contains reusable extraction workflows; each execution retains its configuration, raw source pages, readable text, every LLM attempt, and a combined JSON or CSV export.

## What the proof of concept includes

- Projects that group related scraping runs and data conversations
- A default cross-project task table with active-first ordering, project/status filters, and sortable project/status/updated columns
- Editable multi-URL workflows with extraction instructions and a JSON or CSV output definition
- Explicit execution: saving or editing a workflow never runs it
- A formatting, indentation, line-number, and validation-aware inline JSON editor
- AI-assisted JSON Schema suggestions based on one sample page and the current instructions
- Two processing engines: LLM extraction for ambiguous pages, or deterministic Nokogiri CSS/XPath rules
- AI-assisted selector-rule setup plus a no-LLM visual preview against the first URL
- Sandboxed source-HTML highlights, exact JSON/CSV output previews, and per-field selector diagnostics
- A shared six-hour setup-page cache so previews and suggestions reuse one HTML download and Nokogiri parse
- Independent, cached recommendations for JSON Schema design and executable selector rules
- Manual selector editing for text, HTML, attributes, repeated values, URL resolution, and safe transforms
- Selectable page representations: hybrid text/structured HTML, visible text, metadata/media, or raw HTML
- Manual, hourly, daily, weekly, and monthly execution schedules
- Server-rendered HTML fetching with public-network safeguards
- Nokogiri-based text extraction while retaining the original HTML
- Background processing with separate status and failure tracking for each URL
- Durable background operations for setup prefetch, schema/rule recommendations, and project chat
- Idempotent operation submission, transient retries, status polling, and user-requested cancellation
- Conditional HTTP revalidation with ETag/Last-Modified and content digests
- OpenAI-compatible LLM boundary configured for OpenRouter
- Separate, saved setup, extraction, and project-chat models
- Polymorphic LLM request audit logs with exact prompts, payloads, raw responses, timing, usage, and errors
- Project/workflow usage summaries for tokens, reported cost, latency, failures, and models
- A configurable prompt-size budget that samples oversized input before it reaches the provider
- Per-source outputs, combined exports, prompts, raw model responses, and token usage
- Project-scoped chat over the latest completed results

## Setup

ParserAI uses Ruby 3.4, Rails 8.1, SQLite, Hotwire, and Tailwind.

```sh
bundle install
bin/rails db:prepare
OPENROUTER_API_KEY=your_key bin/dev
```

Open `http://localhost:3000`. The API key is required only for LLM extraction, chat, and AI-assisted setup. Selector-rule tests and executions do not require it.

See `.env.example` for every configuration option. ParserAI reads process environment variables directly; export them in your shell or use your preferred local environment manager.

### Provider configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENROUTER_API_KEY` | — | OpenRouter credential |
| `LLM_API_KEY` | — | Provider-neutral credential used when the OpenRouter-specific key is absent |
| `LLM_BASE_URL` | `https://openrouter.ai/api/v1` | OpenAI-compatible API base URL |
| `SETUP_MODEL` | `openrouter/auto` | Default schema and selector-rule suggestion model |
| `EXTRACTION_MODEL` | `openrouter/auto` | Default structured page-extraction model |
| `CHAT_MODEL` | `openrouter/auto` | Default project data-chat model |
| `OPENROUTER_APP_NAME` | `ParserAI` | Optional OpenRouter app attribution title |
| `OPENROUTER_SITE_URL` | — | Optional OpenRouter app attribution URL |
| `LLM_REQUEST_TIMEOUT` | `180` | API timeout in seconds |
| `LLM_MAX_PROMPT_CHARS` | `120000` | Total character budget across messages in one provider request |

The adapter lives in `app/services/llm/client.rb`. Model IDs use OpenRouter's `author/model` format; `openrouter/auto` delegates selection to OpenRouter. Defaults come from the environment, and the UI can override them per workflow (setup and extraction) or per project (chat). Each execution snapshots its extraction model, so later workflow edits do not alter historical runs.

## Data model

```text
Project
├── AsyncOperation (durable setup and chat workflow lifecycle)
├── LlmRequest (project chat and pre-workflow setup API audit)
├── ScrapeRun
│   ├── AsyncOperation (durable task setup lifecycle)
│   ├── ScrapeExecution (immutable configuration snapshot)
│   │   ├── ScrapeSource (URL, raw HTML, readable text, fetch metadata)
│   │   │   └── ExtractionOutput (successful or failed LLM attempt)
│   │   └── ExtractionOutput (combined export manifest)
│   └── LlmRequest (polymorphic task audit with optional execution/source context)
└── ChatMessage
```

Editing a workflow does not alter previous execution snapshots or outputs. Every manual or scheduled execution creates fresh source and output records.

Every outbound OpenRouter chat-completions call is recorded before it is sent and finalized with the raw provider response or error. API credentials and authorization headers are never stored. Request payloads can contain page content and project data, so treat database access and backups as sensitive.

`AsyncOperation` and `LlmRequest` intentionally describe different levels. An operation is the user-visible workflow and may be retried or make more than one provider call; each `LlmRequest` is one exact HTTP API attempt. Both remain attached to the project or saved workflow that created them.

## Processing flow

1. Save and revise the workflow without fetching pages or calling the model.
2. Choose LLM extraction or deterministic Nokogiri selectors.
3. As the first URL is entered, enqueue a reusable page snapshot with Nokogiri only—no LLM request is made. The browser polls the durable operation instead of holding the request open.
4. Optionally enqueue a JSON Schema or selector-rule recommendation. Each action has its own cache and model request; selector recommendations are validated against the saved page before they are returned.
5. In selector mode, preview the rules against the cached first page without creating an execution or calling an LLM. The preview highlights matched HTML, shows the exact one-page JSON/CSV export shape, and reports missing or ambiguous field matches. Refresh explicitly when a new source snapshot is needed.
6. Run manually, or let the scheduler create an execution from the latest saved configuration.
7. Revalidate each URL with its saved ETag or Last-Modified value when available. A 304 reuses the prior raw snapshot; changed pages are retained and either processed with selectors or sent to the LLM.
8. Store the rules or model response, parsed result, usage, and any error.
9. Build the execution preview and make it available as JSON or CSV.

Selector rules are a constrained JSON format rather than executable Ruby. A rule set chooses CSS or XPath, a repeated `item_selector`, and named fields that read text, inner HTML, or an attribute. Optional features include multiple values, relative URL resolution, and a fixed allowlist of transforms. Selector syntax is validated before rules are saved; XPath fields should begin with `.//` so they remain scoped to each repeated item.

One page can fail without discarding successful pages in the same execution.

Transient setup-page and provider failures retry up to three times through Solid Queue. Reusing an idempotency key returns the original operation instead of scheduling duplicate work. Cancellation is cooperative: queued work stops immediately, while an in-flight HTTP request is allowed to finish before the operation or execution stops.

### Recurring workflows

Recurring dispatch is database-backed through Solid Queue. `bin/dev` starts the web server, Tailwind watcher, and job worker together. In production, keep `bin/jobs` running alongside the web process. The scheduler checks once per minute and creates due executions; each workflow stores its next scheduled time.

## Tests and checks

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rails tailwindcss:build
bundle exec brakeman --no-pager
bin/rubocop
```

## MVP limitations

- Only public, server-rendered HTTP/HTTPS pages are supported. ParserAI does not execute JavaScript, sign into sites, or bypass CAPTCHAs.
- The fetcher blocks loopback, private, link-local, and reserved network targets. It is designed for public web content, not internal services.
- HTML responses are capped at 5 MB and extracted text at 80,000 characters per page by default.
- Project chat uses recent completed output data up to a configurable character limit; retrieval and embeddings are future enhancements.
- JSON mode guarantees parseable JSON, while the requested schema is currently enforced through prompting and basic application shape checks rather than a full JSON Schema validator.

## Deferred scaling options

SQLite remains the intentional database for the current workload. If concurrent workers or write contention become a constraint, PostgreSQL is the planned migration path; no PostgreSQL-specific behavior is required by the current implementation.

Raw HTML, prompts, and responses also remain in the database for straightforward local operation and debugging. Moving large payloads to object storage with database metadata and retention policies is a sensible later optimization, but object storage is not configured now.

Review a site's terms, robots policy, copyright rules, and applicable privacy requirements before collecting its content.
