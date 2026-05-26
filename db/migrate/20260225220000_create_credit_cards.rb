# frozen_string_literal: true

class CreateCreditCards < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_cards do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :bank_name
      t.string :card_type
      t.decimal :annual_fee, precision: 10, scale: 2, default: 0
      t.decimal :fee_waiver_spend, precision: 10, scale: 2
      t.jsonb :rewards_structure, default: {}
      t.text :notes

      t.timestamps
    end
  end
end
