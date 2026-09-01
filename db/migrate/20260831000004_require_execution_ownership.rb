class RequireExecutionOwnership < ActiveRecord::Migration[8.1]
  def up
    change_column_null :scrape_sources, :scrape_execution_id, false
    change_column_null :extraction_outputs, :scrape_execution_id, false
  end

  def down
    change_column_null :extraction_outputs, :scrape_execution_id, true
    change_column_null :scrape_sources, :scrape_execution_id, true
  end
end
