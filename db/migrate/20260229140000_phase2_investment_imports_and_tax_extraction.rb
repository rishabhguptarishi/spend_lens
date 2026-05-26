# frozen_string_literal: true

class Phase2InvestmentImportsAndTaxExtraction < ActiveRecord::Migration[8.0]
  def change
    create_table :investment_import_batches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :investment_account, foreign_key: true
      t.string :source, null: false
      t.string :status, default: 'preview', null: false
      t.integer :financial_year_start, null: false
      t.jsonb :preview_rows, default: []
      t.jsonb :column_mapping, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :investment_import_batches, [:user_id, :status]

    change_table :itr_tax_documents, bulk: true do |t|
      t.string :extraction_status, default: 'pending', null: false
      t.jsonb :confirmed_data, default: {}
    end
  end
end
