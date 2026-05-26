class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.references :statement, null: false, foreign_key: true
      t.references :category, null: true, foreign_key: true
      t.date :date
      t.string :description
      t.decimal :amount
      t.string :transaction_type
      t.string :merchant

      t.timestamps
    end
  end
end
