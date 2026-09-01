class SplitSetupRecommendationCache < ActiveRecord::Migration[8.1]
  def up
    add_column :setup_page_snapshots, :schema_cache_key, :string
    add_column :setup_page_snapshots, :selector_rules_cache_key, :string
    add_column :setup_page_snapshots, :schema_generated_at, :datetime
    add_column :setup_page_snapshots, :selector_rules_generated_at, :datetime

    execute <<~SQL.squish
      UPDATE setup_page_snapshots
      SET schema_cache_key = ai_cache_key,
          selector_rules_cache_key = ai_cache_key,
          schema_generated_at = ai_generated_at,
          selector_rules_generated_at = ai_generated_at
    SQL

    remove_column :setup_page_snapshots, :ai_cache_key
    remove_column :setup_page_snapshots, :ai_generated_at
  end

  def down
    add_column :setup_page_snapshots, :ai_cache_key, :string
    add_column :setup_page_snapshots, :ai_generated_at, :datetime

    execute <<~SQL.squish
      UPDATE setup_page_snapshots
      SET ai_cache_key = COALESCE(schema_cache_key, selector_rules_cache_key),
          ai_generated_at = COALESCE(schema_generated_at, selector_rules_generated_at)
    SQL

    remove_column :setup_page_snapshots, :schema_cache_key
    remove_column :setup_page_snapshots, :selector_rules_cache_key
    remove_column :setup_page_snapshots, :schema_generated_at
    remove_column :setup_page_snapshots, :selector_rules_generated_at
  end
end
