# frozen_string_literal: true

class OptimizeTransactionsAndSyncFlags < ActiveRecord::Migration[8.0]
  def change
    add_index :transactions, [:statement_id, :date], name: 'index_transactions_on_statement_id_and_date'
    add_index :transactions, [:date, :transaction_type], name: 'index_transactions_on_date_and_type'

    add_column :itr_tax_documents, :ledger_synced_at, :datetime
    add_index :itr_tax_documents, :ledger_synced_at
  end
end
