class CreateLlmRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_requests do |t|
      t.references :loggable, polymorphic: true, null: false
      t.references :scrape_execution, foreign_key: true
      t.references :scrape_source, foreign_key: true
      t.string :purpose, null: false
      t.string :provider, null: false, default: "openrouter"
      t.string :endpoint, null: false
      t.string :model_requested, null: false
      t.string :model_returned
      t.string :provider_request_id
      t.string :status, null: false, default: "pending"
      t.json :request_payload, null: false, default: {}
      t.json :response_payload
      t.json :usage
      t.string :error_class
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_ms
      t.timestamps
    end

    add_index :llm_requests, %i[status created_at]
    add_index :llm_requests, :provider_request_id
  end
end
