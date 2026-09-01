class CreateAsyncOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :async_operations do |t|
      t.references :operable, polymorphic: true, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "queued"
      t.string :idempotency_key, null: false
      t.json :input, null: false, default: {}
      t.json :result
      t.integer :attempts, null: false, default: 0
      t.string :error_class
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancel_requested_at
      t.timestamps
    end

    add_index :async_operations, :idempotency_key, unique: true
    add_index :async_operations, %i[status created_at]
    add_index :async_operations, %i[operable_type operable_id created_at],
      name: "index_async_operations_on_operable_and_created_at"

    add_reference :llm_requests, :async_operation, foreign_key: true
  end
end
