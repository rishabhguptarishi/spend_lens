class CreateCategoryRules < ActiveRecord::Migration[8.0]
  def change
    create_table :category_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :merchant_pattern, null: false
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
    add_index :category_rules, [:user_id, :merchant_pattern]
  end
end
