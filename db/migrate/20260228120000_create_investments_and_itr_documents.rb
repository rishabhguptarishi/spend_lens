# frozen_string_literal: true

class CreateInvestmentsAndItrDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :investment_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider
      t.string :account_kind, default: 'other', null: false
      t.text :notes
      t.timestamps
    end

    create_table :investment_holdings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :investment_account, null: false, foreign_key: true
      t.string :asset_class, null: false
      t.string :name, null: false
      t.string :symbol
      t.string :folio
      t.decimal :units, precision: 18, scale: 6, default: 0
      t.decimal :avg_cost, precision: 14, scale: 2, default: 0
      t.decimal :invested_amount, precision: 14, scale: 2, default: 0
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    create_table :investment_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :investment_account, foreign_key: true
      t.references :investment_holding, foreign_key: true
      t.references :transaction, foreign_key: true
      t.date :date, null: false
      t.string :kind, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.decimal :units, precision: 18, scale: 6
      t.string :description
      t.string :source, default: 'manual', null: false
      t.integer :financial_year_start, null: false
      t.string :asset_class
      t.timestamps
    end

    add_index :investment_transactions, [:user_id, :financial_year_start],
              name: "index_inv_txns_on_user_fy"
    add_index :investment_transactions, [:user_id, :date]

    create_table :investment_suggestions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :transaction, null: false, foreign_key: true
      t.string :suggested_asset_class, null: false
      t.string :suggested_kind, null: false
      t.string :suggested_account_name
      t.string :status, default: 'pending', null: false
      t.timestamps
    end

    add_index :investment_suggestions, [:user_id, :status]
    add_index :investment_suggestions, :transaction_id, unique: true

    create_table :itr_tax_documents do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :financial_year_start, null: false
      t.string :document_type, null: false
      t.string :status, default: 'uploaded', null: false
      t.jsonb :extracted_data, default: {}
      t.timestamps
    end

    add_index :itr_tax_documents, [:user_id, :financial_year_start, :document_type],
              unique: true, name: 'index_itr_docs_on_user_fy_type'
  end
end
