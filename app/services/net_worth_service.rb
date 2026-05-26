# frozen_string_literal: true

# Approximate net worth: investment cost basis + estimated bank balances from transaction flows.
class NetWorthService
  def initialize(user)
    @user = user
  end

  def call
    investments = @user.investment_holdings.sum(:invested_amount).to_f
    banks = bank_estimates_sql
    total_bank = banks.sum { |b| b[:estimated_balance].to_f }

    {
      total_invested: investments,
      bank_estimates: banks,
      total_bank: total_bank,
      credit_card_annual_fees: @user.credit_cards.sum(:annual_fee).to_f,
      net_worth_approx: investments + total_bank,
      disclaimer: 'Approximate only — no live NAV or full account aggregation.',
      by_asset_class: @user.investment_holdings.group(:asset_class).sum(:invested_amount),
    }
  end

  private

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
