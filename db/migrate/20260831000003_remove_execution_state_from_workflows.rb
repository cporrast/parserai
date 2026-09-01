class RemoveExecutionStateFromWorkflows < ActiveRecord::Migration[8.1]
  def up
    remove_index :scrape_runs, :status
    remove_columns :scrape_runs, :status, :error_message, :started_at, :completed_at
  end

  def down
    add_column :scrape_runs, :status, :string, null: false, default: "queued"
    add_column :scrape_runs, :error_message, :text
    add_column :scrape_runs, :started_at, :datetime
    add_column :scrape_runs, :completed_at, :datetime
    add_index :scrape_runs, :status
  end
end
