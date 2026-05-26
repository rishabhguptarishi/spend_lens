# frozen_string_literal: true

class FixMisclassifiedCreditTransactions < ActiveRecord::Migration[7.2]
  CREDIT_KEYWORDS = /\b(SALARY|CRV|CREDIT|REFUND|REVERSAL|INTEREST|DEPOSIT|A\s*AINT|NEFT\s+CR|RTGS\s+CR)\b/i

  def up
    # Fix transactions that have credit keywords in description but were stored as debit
    Transaction.where(transaction_type: 'debit').find_each do |tx|
      next unless tx.description.to_s.match?(CREDIT_KEYWORDS)

      tx.update_column(:transaction_type, 'credit')
    end
  end

  def down
    # No reversible fix - we can't know which were originally debit
  end
end
