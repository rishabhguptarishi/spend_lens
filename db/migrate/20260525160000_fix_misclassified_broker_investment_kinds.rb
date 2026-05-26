# frozen_string_literal: true

# Repairs investment data that was created while the broker detection rule
# (Zerodha/Groww/etc.) incorrectly used kind: 'transfer_out'. Those rows were
# debits going INTO investments, so the correct kind is 'buy'. We flip the
# kind on both the historical investment_transactions and the originating
# investment_suggestions, then recompute affected holdings.
class FixMisclassifiedBrokerInvestmentKinds < ActiveRecord::Migration[8.0]
  def up
    # Reset model column info in case prior migrations changed anything.
    InvestmentTransaction.reset_column_information
    InvestmentSuggestion.reset_column_information
    InvestmentHolding.reset_column_information

    affected_holding_ids = InvestmentTransaction
      .where(source: 'bank_detect', asset_class: 'stock', kind: 'transfer_out')
      .where.not(investment_holding_id: nil)
      .distinct
      .pluck(:investment_holding_id)

    say_with_time "Flipping bank_detect/stock/transfer_out → buy on investment_transactions" do
      InvestmentTransaction
        .where(source: 'bank_detect', asset_class: 'stock', kind: 'transfer_out')
        .update_all(kind: 'buy')
    end

    say_with_time "Flipping accepted broker suggestions to suggested_kind=buy" do
      InvestmentSuggestion
        .where(suggested_asset_class: 'stock', suggested_kind: 'transfer_out')
        .update_all(suggested_kind: 'buy')
    end

    say_with_time "Recomputing #{affected_holding_ids.size} affected holdings" do
      InvestmentHolding.where(id: affected_holding_ids).find_each(&:recompute_totals!)
    end
  end

  def down
    # We don't reverse — the previous state was a bug. Leaving this as a no-op
    # so a rollback doesn't accidentally re-corrupt user data.
    say "Down is intentionally a no-op (fixing data corruption is one-way)."
  end
end
