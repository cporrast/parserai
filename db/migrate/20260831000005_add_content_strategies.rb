class AddContentStrategies < ActiveRecord::Migration[8.1]
  def change
    add_column :scrape_runs, :content_strategy, :string, null: false, default: "standard"
    add_column :scrape_executions, :content_strategy, :string, null: false, default: "standard"
    add_column :scrape_sources, :structured_data, :json
  end
end
