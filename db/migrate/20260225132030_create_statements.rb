class CreateStatements < ActiveRecord::Migration[8.0]
  def change
    create_table :statements do |t|
      t.references :bank_account, null: false, foreign_key: true
      t.integer :month
      t.integer :year
      t.string :status, default: 'pending'

      t.timestamps
    end
  end
end
