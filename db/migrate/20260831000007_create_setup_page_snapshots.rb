class CreateSetupPageSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :setup_page_snapshots do |t|
      t.string :url_digest, null: false
      t.text :url, null: false
      t.text :final_url
      t.integer :http_status
      t.string :content_type
      t.string :title
      t.text :raw_html
      t.text :extracted_text
      t.json :structured_data
      t.datetime :fetched_at
      t.string :ai_cache_key
      t.text :suggested_schema
      t.text :suggested_rules
      t.datetime :ai_generated_at
      t.timestamps

      t.index :url_digest, unique: true
      t.index :fetched_at
    end
  end
end
