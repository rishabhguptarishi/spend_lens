# frozen_string_literal: true

class AddUniqueStatementPerBankPeriod < ActiveRecord::Migration[8.0]
  def change
    add_index :statements, [:bank_account_id, :month, :year],
              name: 'index_statements_on_bank_account_month_year'
  end
end
