class CreateParserAiCore < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    create_table :scrape_runs do |t|
      t.references :project, null: false, foreign_key: true
      t.text :instructions, null: false
      t.string :output_format, null: false, default: "json"
      t.text :output_schema, null: false
      t.string :status, null: false, default: "queued"
      t.string :extraction_model
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :scrape_runs, :status

    create_table :scrape_sources do |t|
      t.references :scrape_run, null: false, foreign_key: true
      t.text :url, null: false
      t.integer :position, null: false, default: 0
      t.string :status, null: false, default: "queued"
      t.text :final_url
      t.integer :http_status
      t.string :content_type
      t.string :title
      t.text :raw_html
      t.text :extracted_text
      t.datetime :fetched_at
      t.text :error_message
      t.timestamps
    end
    add_index :scrape_sources, %i[scrape_run_id position], unique: true

    create_table :extraction_outputs do |t|
      t.references :scrape_run, null: false, foreign_key: true
      t.references :scrape_source, null: true, foreign_key: true
      t.string :kind, null: false, default: "source"
      t.string :status, null: false, default: "completed"
      t.string :model
      t.text :prompt
      t.text :raw_response
      t.json :data
      t.json :usage
      t.text :error_message
      t.datetime :generated_at
      t.timestamps
    end
    add_index :extraction_outputs, %i[scrape_run_id kind]

    create_table :chat_messages do |t|
      t.references :project, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.string :model
      t.json :metadata
      t.timestamps
    end
  end
end
