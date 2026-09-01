class ScopeAsyncOperationIdempotency < ActiveRecord::Migration[8.1]
  def change
    remove_index :async_operations, :idempotency_key
    add_index :async_operations,
      %i[operable_type operable_id kind idempotency_key],
      unique: true,
      name: "index_async_operations_on_owner_kind_and_idempotency"
  end
end
