# frozen_string_literal: true

class InvestmentsController < ApplicationController
  before_action :authenticate_user!

  def index
    fy = financial_year_param

    # Phase 4 §5.7: /investments is now rendered as a list of
    # INSTRUMENTS (one row per real-world security/account), with
    # cross-source attestation badges. We group holdings client-side
    # by identity_key (or by id when key is nil), with their materialized
    # positions hanging off each row.
    holdings = current_user.investment_holdings.includes(:investment_account).to_a
    positions = current_user.investment_positions.includes(:investment_holding).to_a
    # group_by, NOT index_by — same holding can have multiple positions
    # (one per custodian) and we need all of them to roll up correctly.
    positions_by_holding = positions.group_by(&:investment_holding_id)

    confirmed_by_index = active_confirmed_by_for(holdings)

    fy_txs = current_user.investment_transactions.for_fy(fy).active

    by_class = current_user.investment_holdings.group(:asset_class).count
    fy_contributions = fy_txs.where(kind: %w[buy contribution sip transfer_in]).sum(:amount).to_f
    fy_sells = fy_txs.where(kind: %w[sell transfer_out maturity]).sum(:amount).to_f

    instruments = build_instruments(holdings, positions_by_holding, confirmed_by_index)
    total_invested = instruments.sum { |i| i[:cost_basis] }
    total_current  = instruments.sum { |i| i[:current_value] || i[:cost_basis] }

    render inertia: 'Investments/Index',
           props: {
             financial_year_start: fy,
             financial_year_label: FinancialYear.label(fy),
             years: FinancialYear.available_years,
             instruments: instruments,
             holdings: holdings.map { |h| holding_json(h, positions_by_holding[h.id]) },  # kept for compatibility
             summary: {
               instrument_count: instruments.size,
               holdings_count: holdings.size,
               total_invested: total_invested,
               total_current_value: total_current,
               unrealized_gain: total_current - total_invested,
               by_asset_class: by_class,
               fy_contributions: fy_contributions,
               fy_sells: fy_sells,
               fy_transaction_count: fy_txs.count,
               nav_priced_count: positions.count(&:priced_with_nav?),
             },
             pending_suggestions_count: current_user.investment_suggestions.pending.count,
             accounts: current_user.investment_accounts.order(:name).map { |a| account_json(a) },
           }
  end

  def activity
    fy = financial_year_param
    txs = current_user.investment_transactions
                      .active
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

  # Phase 4 §5.7 row 2: three tabs (auto_resolved / likely_match /
  # unknown) so users can triage with confidence-aware bulk actions.
  def suggestions
    pending = current_user.investment_suggestions
                          .pending
                          .includes(source_transaction: { statement: :bank_account })
                          .order(created_at: :desc)

    grouped = pending.group_by(&:match_bucket)
    counts = InvestmentSuggestion::MATCH_BUCKETS.index_with { |b| grouped[b]&.size.to_i }

    render inertia: 'Investments/Suggestions',
           props: {
             suggestions: pending.map { |s| suggestion_json(s) },
             buckets: counts,
             bucket_labels: {
               'auto_resolved' => 'Auto-resolved (high confidence)',
               'likely_match'  => 'Likely match',
               'unknown'       => 'Needs review',
             },
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

  # Group holdings by identity_key (or holding-id when key is nil).
  # Each instrument carries the rolled-up cost_basis/current_value across
  # custodians, plus per-custodian breakdown so the UI can show
  # "Reliance — ₹50,000 (₹30k at Zerodha + ₹20k at Groww)".
  def build_instruments(holdings, positions_by_holding, confirmed_by_index)
    holdings.group_by { |h| h.identity_key.presence || "holding_id:#{h.id}" }.map do |key, hs|
      sample = hs.first
      positions = hs.flat_map { |h| Array(positions_by_holding[h.id]) }
      cost_basis = positions.sum(&:cost_basis).to_f.then { |v| v.zero? ? hs.sum { |h| h.invested_amount.to_f } : v }
      current_value = positions.filter_map { |p| p.current_value&.to_f }.sum
      total_units   = positions.sum(&:units).to_f

      confirmed_sources = hs.flat_map { |h| confirmed_by_index[h.id] || [] }.flatten.uniq

      {
        identity_key: key,
        name: sample.name,
        asset_class: sample.asset_class,
        symbol: sample.symbol,
        folio: sample.folio,
        units: total_units,
        cost_basis: cost_basis.round(2),
        current_value: current_value.positive? ? current_value.round(2) : nil,
        nav: positions.find(&:priced_with_nav?)&.current_nav&.to_f,
        nav_as_of: positions.find(&:priced_with_nav?)&.as_of_date,
        confirmed_by: confirmed_sources,
        custodians: positions.map { |p| { name: p.custodian, cost_basis: p.cost_basis.to_f, current_value: p.current_value&.to_f, units: p.units.to_f } },
        accounts: hs.map { |h| { id: h.investment_account_id, name: h.investment_account&.name } }.uniq,
        metadata: sample.metadata,
      }
    end.sort_by { |i| -(i[:current_value] || i[:cost_basis] || 0) }
  end

  # Pre-fetch confirmed_by arrays per holding so we don't N+1 across
  # transactions in #build_instruments.
  def active_confirmed_by_for(holdings)
    holding_ids = holdings.map(&:id)
    return {} if holding_ids.empty?

    current_user.investment_transactions
      .active
      .where(investment_holding_id: holding_ids)
      .where.not(confirmed_by: [])
      .pluck(:investment_holding_id, :confirmed_by, :source)
      .group_by(&:first)
      .transform_values { |rows| rows.map { |(_, cb, src)| ([src] + Array(cb)).uniq }.flatten.uniq }
  end

  def holding_json(h, positions = nil)
    primary = Array(positions).first
    {
      id: h.id,
      name: h.name,
      asset_class: h.asset_class,
      symbol: h.symbol,
      units: h.units.to_f,
      invested_amount: h.invested_amount.to_f,
      cost_basis: primary&.cost_basis&.to_f || h.invested_amount.to_f,
      current_value: primary&.current_value&.to_f,
      current_nav: primary&.current_nav&.to_f,
      account: h.investment_account&.name,
      account_id: h.investment_account_id,
      identity_key: h.identity_key,
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
      source_priority: t.source_priority,
      confirmed_by: Array(t.confirmed_by),
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
      confidence: s.confidence.to_f,
      match_bucket: s.match_bucket,
      metadata: s.metadata,
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
