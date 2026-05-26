class AddIsRecurringToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :is_recurring, :boolean, default: false
  end
end
