# frozen_string_literal: true

class InvestmentsController < ApplicationController
  before_action :authenticate_user!

  def index
    fy = financial_year_param
    holdings = current_user.investment_holdings.includes(:investment_account)
    fy_txs = current_user.investment_transactions.for_fy(fy)

    by_class = holdings.group(:asset_class).count
    total_invested = holdings.sum(:invested_amount).to_f
    fy_contributions = fy_txs.where(kind: %w[buy contribution sip transfer_in]).sum(:amount).to_f
    fy_sells = fy_txs.where(kind: %w[sell transfer_out maturity]).sum(:amount).to_f

    render inertia: 'Investments/Index',
           props: {
             financial_year_start: fy,
             financial_year_label: FinancialYear.label(fy),
             years: FinancialYear.available_years,
             holdings: holdings.map { |h| holding_json(h) },
             summary: {
               holdings_count: holdings.count,
               total_invested: total_invested,
               by_asset_class: by_class,
               fy_contributions: fy_contributions,
               fy_sells: fy_sells,
               fy_transaction_count: fy_txs.count,
             },
             pending_suggestions_count: current_user.investment_suggestions.pending.count,
             accounts: current_user.investment_accounts.order(:name).map { |a| account_json(a) },
           }
  end

  def activity
    fy = financial_year_param
    txs = current_user.investment_transactions
                      .for_fy(fy)
                      .includes(:investment_account, :investment_holding)
                      .order(date: :desc)

    render inertia: 'Investments/Activity',
           props: {
             financial_year_start: fy,
             financial_year_label: FinancialYear.label(fy),
             years: FinancialYear.available_years,
             transactions: txs.map { |t| investment_transaction_json(t) },
             kinds: InvestmentTransaction::KINDS,
             asset_classes: InvestmentHolding::ASSET_CLASSES,
           }
  end

  def suggestions
    suggestions = current_user.investment_suggestions
                                .pending
                                .includes(source_transaction: { statement: :bank_account })
                                .order(created_at: :desc)

    render inertia: 'Investments/Suggestions',
           props: {
             suggestions: suggestions.map { |s| suggestion_json(s) },
           }
  end

  # Re-runs InvestmentDetectionService against the user's full bank
  # transaction history. Useful after new detection rules ship — every
  # MOB-TD / FRSB / AMC SIP that was uploaded before the rules existed
  # gets picked up and surfaced as a fresh pending suggestion.
  def rescan
    count = InvestmentDetectionService.new(current_user).scan_transactions!
    redirect_to investments_suggestions_path,
                notice: count.positive? ? "Found #{count} new investment suggestion#{'s' if count != 1}." : "No new suggestions found."
  end

  private

  def financial_year_param
    year = (params[:fy] || params[:year] || FinancialYear.current_start_year).to_i
    available = FinancialYear.available_years
    available.include?(year) ? year : FinancialYear.current_start_year
  end

  def holding_json(h)
    {
      id: h.id,
      name: h.name,
      asset_class: h.asset_class,
      symbol: h.symbol,
      units: h.units.to_f,
      invested_amount: h.invested_amount.to_f,
      account: h.investment_account&.name,
      account_id: h.investment_account_id,
    }
  end

  def account_json(a)
    { id: a.id, name: a.name, provider: a.provider, account_kind: a.account_kind }
  end

  def investment_transaction_json(t)
    {
      id: t.id,
      date: t.date,
      kind: t.kind,
      amount: t.amount.to_f,
      description: t.description,
      asset_class: t.asset_class,
      source: t.source,
      account: t.investment_account&.name,
      holding: t.investment_holding&.name,
    }
  end

  def suggestion_json(s)
    tx = s.source_transaction
    {
      id: s.id,
      suggested_asset_class: s.suggested_asset_class,
      suggested_kind: s.suggested_kind,
      suggested_account_name: s.suggested_account_name,
      transaction: {
        id: tx.id,
        date: tx.date,
        description: tx.description,
        amount: tx.amount.to_f,
        transaction_type: tx.transaction_type,
        bank_account: tx.statement&.bank_account&.name,
      },
    }
  end
end
