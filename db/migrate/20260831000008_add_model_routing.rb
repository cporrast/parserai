class AddModelRouting < ActiveRecord::Migration[8.1]
  def change
    add_column :scrape_runs, :setup_model, :string
    add_column :projects, :chat_model, :string
  end
end
