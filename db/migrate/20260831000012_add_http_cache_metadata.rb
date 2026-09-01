class AddHttpCacheMetadata < ActiveRecord::Migration[8.1]
  def change
    change_table :setup_page_snapshots, bulk: true do |t|
      t.string :etag
      t.string :last_modified
      t.string :content_digest
    end

    change_table :scrape_sources, bulk: true do |t|
      t.string :etag
      t.string :last_modified
      t.string :content_digest
      t.boolean :content_reused, null: false, default: false
    end

    add_column :scrape_executions, :cancel_requested_at, :datetime

    add_index :scrape_sources, %i[scrape_run_id url]
  end
end
