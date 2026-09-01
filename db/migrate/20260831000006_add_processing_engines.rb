class AddProcessingEngines < ActiveRecord::Migration[8.1]
  def change
    add_column :scrape_runs, :processing_mode, :string, null: false, default: "llm"
    add_column :scrape_runs, :selector_rules, :text
    add_column :scrape_executions, :processing_mode, :string, null: false, default: "llm"
    add_column :scrape_executions, :selector_rules, :text
  end
end
