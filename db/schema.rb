# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_31_000013) do
  create_table "async_operations", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "cancel_requested_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "error_class"
    t.text "error_message"
    t.string "idempotency_key", null: false
    t.json "input", default: {}, null: false
    t.string "kind", null: false
    t.integer "operable_id", null: false
    t.string "operable_type", null: false
    t.json "result"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["operable_type", "operable_id", "created_at"], name: "index_async_operations_on_operable_and_created_at"
    t.index ["operable_type", "operable_id", "kind", "idempotency_key"], name: "index_async_operations_on_owner_kind_and_idempotency", unique: true
    t.index ["operable_type", "operable_id"], name: "index_async_operations_on_operable"
    t.index ["status", "created_at"], name: "index_async_operations_on_status_and_created_at"
  end

  create_table "chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.json "metadata"
    t.string "model"
    t.integer "project_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_chat_messages_on_project_id"
  end

  create_table "extraction_outputs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.text "error_message"
    t.datetime "generated_at"
    t.string "kind", default: "source", null: false
    t.string "model"
    t.text "prompt"
    t.text "raw_response"
    t.integer "scrape_execution_id", null: false
    t.integer "scrape_run_id", null: false
    t.integer "scrape_source_id"
    t.string "status", default: "completed", null: false
    t.datetime "updated_at", null: false
    t.json "usage"
    t.index ["scrape_execution_id"], name: "index_extraction_outputs_on_scrape_execution_id"
    t.index ["scrape_run_id", "kind"], name: "index_extraction_outputs_on_scrape_run_id_and_kind"
    t.index ["scrape_run_id"], name: "index_extraction_outputs_on_scrape_run_id"
    t.index ["scrape_source_id"], name: "index_extraction_outputs_on_scrape_source_id"
  end

  create_table "llm_requests", force: :cascade do |t|
    t.integer "async_operation_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "endpoint", null: false
    t.string "error_class"
    t.text "error_message"
    t.integer "loggable_id", null: false
    t.string "loggable_type", null: false
    t.string "model_requested", null: false
    t.string "model_returned"
    t.string "provider", default: "openrouter", null: false
    t.string "provider_request_id"
    t.string "purpose", null: false
    t.json "request_payload", default: {}, null: false
    t.json "response_payload"
    t.integer "scrape_execution_id"
    t.integer "scrape_source_id"
    t.datetime "started_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.json "usage"
    t.index ["async_operation_id"], name: "index_llm_requests_on_async_operation_id"
    t.index ["loggable_type", "loggable_id"], name: "index_llm_requests_on_loggable"
    t.index ["provider_request_id"], name: "index_llm_requests_on_provider_request_id"
    t.index ["scrape_execution_id"], name: "index_llm_requests_on_scrape_execution_id"
    t.index ["scrape_source_id"], name: "index_llm_requests_on_scrape_source_id"
    t.index ["status", "created_at"], name: "index_llm_requests_on_status_and_created_at"
  end

  create_table "projects", force: :cascade do |t|
    t.string "chat_model"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "scrape_executions", force: :cascade do |t|
    t.datetime "cancel_requested_at"
    t.datetime "completed_at"
    t.string "content_strategy", default: "standard", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "extraction_model"
    t.text "instructions", null: false
    t.string "output_format", null: false
    t.text "output_schema", null: false
    t.string "processing_mode", default: "llm", null: false
    t.integer "scrape_run_id", null: false
    t.text "selector_rules"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "trigger", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["scrape_run_id", "created_at"], name: "index_scrape_executions_on_scrape_run_id_and_created_at"
    t.index ["scrape_run_id"], name: "index_scrape_executions_on_scrape_run_id"
    t.index ["status"], name: "index_scrape_executions_on_status"
  end

  create_table "scrape_runs", force: :cascade do |t|
    t.string "content_strategy", default: "standard", null: false
    t.datetime "created_at", null: false
    t.string "extraction_model"
    t.text "instructions", null: false
    t.datetime "next_run_at"
    t.string "output_format", default: "json", null: false
    t.text "output_schema", null: false
    t.string "processing_mode", default: "llm", null: false
    t.integer "project_id", null: false
    t.string "recurrence", default: "manual", null: false
    t.text "selector_rules"
    t.string "setup_model"
    t.datetime "updated_at", null: false
    t.text "urls_text"
    t.index ["project_id"], name: "index_scrape_runs_on_project_id"
  end

  create_table "scrape_sources", force: :cascade do |t|
    t.string "content_digest"
    t.boolean "content_reused", default: false, null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "etag"
    t.text "extracted_text"
    t.datetime "fetched_at"
    t.text "final_url"
    t.integer "http_status"
    t.string "last_modified"
    t.integer "position", default: 0, null: false
    t.text "raw_html"
    t.integer "scrape_execution_id", null: false
    t.integer "scrape_run_id", null: false
    t.string "status", default: "queued", null: false
    t.json "structured_data"
    t.string "title"
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.index ["scrape_execution_id", "position"], name: "index_scrape_sources_on_scrape_execution_id_and_position", unique: true
    t.index ["scrape_execution_id"], name: "index_scrape_sources_on_scrape_execution_id"
    t.index ["scrape_run_id", "url"], name: "index_scrape_sources_on_scrape_run_id_and_url"
    t.index ["scrape_run_id"], name: "index_scrape_sources_on_scrape_run_id"
  end

  create_table "setup_page_snapshots", force: :cascade do |t|
    t.string "content_digest"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "etag"
    t.text "extracted_text"
    t.datetime "fetched_at"
    t.text "final_url"
    t.integer "http_status"
    t.string "last_modified"
    t.text "raw_html"
    t.string "schema_cache_key"
    t.datetime "schema_generated_at"
    t.string "selector_rules_cache_key"
    t.datetime "selector_rules_generated_at"
    t.json "structured_data"
    t.text "suggested_rules"
    t.text "suggested_schema"
    t.string "title"
    t.datetime "updated_at", null: false
    t.text "url", null: false
    t.string "url_digest", null: false
    t.index ["fetched_at"], name: "index_setup_page_snapshots_on_fetched_at"
    t.index ["url_digest"], name: "index_setup_page_snapshots_on_url_digest", unique: true
  end

  add_foreign_key "chat_messages", "projects"
  add_foreign_key "extraction_outputs", "scrape_executions"
  add_foreign_key "extraction_outputs", "scrape_runs"
  add_foreign_key "extraction_outputs", "scrape_sources"
  add_foreign_key "llm_requests", "async_operations"
  add_foreign_key "llm_requests", "scrape_executions"
  add_foreign_key "llm_requests", "scrape_sources"
  add_foreign_key "scrape_executions", "scrape_runs"
  add_foreign_key "scrape_runs", "projects"
  add_foreign_key "scrape_sources", "scrape_executions"
  add_foreign_key "scrape_sources", "scrape_runs"
end
