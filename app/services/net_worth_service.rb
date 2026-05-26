# frozen_string_literal: true

# Phase 4 §5.7 row 4 — net worth now reads from the materialized
# InvestmentPosition layer instead of summing InvestmentHolding cost
# basis directly. The Position layer respects supersession, so a user
# with overlapping broker_csv + cdsl_cas data no longer double-counts
# their portfolio.
#
# Output shape extended (BUT backward-compatible): existing UI keys
# (total_invested, by_asset_class, etc.) keep working; new keys
# (total_current_value, unrealized_gain, nav_priced_count) feed the
# Phase 4 UI changes.
class NetWorthService
  def initialize(user)
    @user = user
  end

  def call
    positions = @user.investment_positions.includes(investment_holding: :investment_account).nonzero.to_a

    total_invested = positions.sum(&:cost_basis).to_f
    total_current  = positions.sum(&:best_known_value).to_f
    nav_priced     = positions.count(&:priced_with_nav?)

    banks = bank_estimates_sql
    total_bank = banks.sum { |b| b[:estimated_balance].to_f }

    by_asset_cost = positions.group_by(&:asset_class).transform_values { |ps| ps.sum(&:cost_basis).to_f.round(2) }
    by_asset_value = positions.group_by(&:asset_class).transform_values { |ps| ps.sum(&:best_known_value).to_f.round(2) }

    {
      total_invested: total_invested.round(2),
      total_current_value: total_current.round(2),
      unrealized_gain: (total_current - total_invested).round(2),
      bank_estimates: banks,
      total_bank: total_bank,
      credit_card_annual_fees: @user.credit_cards.sum(:annual_fee).to_f,
      net_worth_approx: (total_current + total_bank).round(2),
      net_worth_cost_basis: (total_invested + total_bank).round(2),
      disclaimer: nav_priced.positive? ? "Live NAV applied to #{nav_priced} of #{positions.size} positions; remainder uses cost basis." : 'NAV unavailable — values shown at cost basis.',
      by_asset_class: by_asset_cost,
      by_asset_class_current: by_asset_value,
      positions: positions.map { |p| position_json(p) },
      nav_priced_count: nav_priced,
      position_count: positions.size,
    }
  end

  private

  def position_json(p)
    holding = p.investment_holding
    {
      id: p.id,
      holding_id: holding&.id,
      name: holding&.name,
      asset_class: p.asset_class,
      custodian: p.custodian,
      units: p.units.to_f,
      cost_basis: p.cost_basis.to_f,
      current_value: p.current_value&.to_f,
      current_nav: p.current_nav&.to_f,
      as_of_date: p.as_of_date,
      unrealized_gain: p.unrealized_gain,
      unrealized_return_pct: p.unrealized_return_pct&.round(2),
      priced_with_nav: p.priced_with_nav?,
    }
  end

  def bank_estimates_sql
    sql = <<~SQL.squish
      SELECT bank_accounts.id,
             bank_accounts.name,
             bank_accounts.bank_name,
             COALESCE(SUM(
               CASE WHEN transactions.transaction_type = 'credit' THEN transactions.amount
                    ELSE -transactions.amount END
             ), 0) AS estimated_balance,
             COUNT(transactions.id) AS transaction_count
      FROM bank_accounts
      LEFT JOIN statements ON statements.bank_account_id = bank_accounts.id
      LEFT JOIN transactions ON transactions.statement_id = statements.id
      WHERE bank_accounts.user_id = :user_id
      GROUP BY bank_accounts.id, bank_accounts.name, bank_accounts.bank_name
    SQL

    rows = ActiveRecord::Base.connection.select_all(
      ActiveRecord::Base.sanitize_sql_array([sql, { user_id: @user.id }])
    )

    rows.map do |r|
      {
        id: r['id'],
        name: r['name'],
        bank_name: r['bank_name'],
        estimated_balance: r['estimated_balance'].to_f.round(2),
        transaction_count: r['transaction_count'].to_i,
      }
    end
  end
end
