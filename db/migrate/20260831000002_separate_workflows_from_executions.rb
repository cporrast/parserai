class SeparateWorkflowsFromExecutions < ActiveRecord::Migration[8.1]
  class LegacyRun < ActiveRecord::Base
    self.table_name = "scrape_runs"
  end

  class LegacySource < ActiveRecord::Base
    self.table_name = "scrape_sources"
  end

  class LegacyOutput < ActiveRecord::Base
    self.table_name = "extraction_outputs"
  end

  class LegacyExecution < ActiveRecord::Base
    self.table_name = "scrape_executions"
  end

  def up
    add_column :scrape_runs, :urls_text, :text
    add_column :scrape_runs, :recurrence, :string, null: false, default: "manual"
    add_column :scrape_runs, :next_run_at, :datetime

    create_table :scrape_executions do |t|
      t.references :scrape_run, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :trigger, null: false, default: "manual"
      t.text :instructions, null: false
      t.string :output_format, null: false
      t.text :output_schema, null: false
      t.string :extraction_model
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :scrape_executions, :status
    add_index :scrape_executions, %i[scrape_run_id created_at]

    add_reference :scrape_sources, :scrape_execution, null: true, foreign_key: true
    add_reference :extraction_outputs, :scrape_execution, null: true, foreign_key: true
    remove_index :scrape_sources, %i[scrape_run_id position]
    add_index :scrape_sources, %i[scrape_execution_id position], unique: true

    backfill_existing_runs
  end

  def down
    remove_index :scrape_sources, %i[scrape_execution_id position]
    add_index :scrape_sources, %i[scrape_run_id position], unique: true
    remove_reference :extraction_outputs, :scrape_execution, foreign_key: true
    remove_reference :scrape_sources, :scrape_execution, foreign_key: true
    drop_table :scrape_executions
    remove_column :scrape_runs, :next_run_at
    remove_column :scrape_runs, :recurrence
    remove_column :scrape_runs, :urls_text
  end

  private

  def backfill_existing_runs
    [ LegacyRun, LegacySource, LegacyOutput, LegacyExecution ].each(&:reset_column_information)

    LegacyRun.find_each do |run|
      sources = LegacySource.where(scrape_run_id: run.id).order(:position)
      run.update_columns(urls_text: sources.pluck(:url).join("\n"))
      next if sources.empty? && LegacyOutput.where(scrape_run_id: run.id).none?

      execution = LegacyExecution.create!(
        scrape_run_id: run.id,
        status: run.status,
        trigger: "manual",
        instructions: run.instructions,
        output_format: run.output_format,
        output_schema: run.output_schema,
        extraction_model: run.extraction_model,
        error_message: run.error_message,
        started_at: run.started_at,
        completed_at: run.completed_at,
        created_at: run.created_at,
        updated_at: run.updated_at
      )
      sources.update_all(scrape_execution_id: execution.id)
      LegacyOutput.where(scrape_run_id: run.id).update_all(scrape_execution_id: execution.id)
    end
  end
end
