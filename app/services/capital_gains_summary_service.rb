# frozen_string_literal: true

# Phase 4 §5.7 — unified capital-gains across pages.
#
# Pre-refactor problem: this service summed every sell row in the FY,
# AND `/itr/reconciliation` did its own AIS heuristic, AND a broker P&L
# tax doc could ALSO contribute its STCG figure separately. Result: a
# user with both a broker_csv import and an uploaded broker P&L PDF
# would see their gains counted twice across the two callouts.
#
# After Phase 1+2 we have:
#   - source_priority on every activity (cdsl_cas=100 → manual=40)
#   - superseded_by_id pointer set by ActivityReconcilerService when a
#     higher-priority source attests to the same event
#
# That lets this service do the right thing: it scans only ACTIVE
# (non-superseded) sells, and surfaces a source breakdown so the UI
# can show "8 of 12 sells confirmed by tax doc" — the doc's §5.7 ask.
#
# The heuristic STCG/LTCG classification is still here (we don't have
# per-trade purchase-date linkage), but it's now SECONDARY to the
# priority-90 tax-doc figure when one exists.
class CapitalGainsSummaryService
  TAX_DOC_PRIORITY = 90 # broker_pl / mf_cg
  STCG_ASSET_CLASSES = %w[mutual_fund stock reit invit].freeze
  LTCG_DEFAULT_ASSET_CLASSES = %w[real_estate bond sgb].freeze

  def initialize(user, financial_year_start:)
    @user = user
    @fy = financial_year_start.to_i
  end

  def call
    @summary ||= build_summary
  end

  def to_csv
    summary = call
    require 'csv'
    CSV.generate do |csv|
      csv << ['Capital gains summary', summary[:financial_year_label]]
      csv << %w[Date Description Asset_class Amount Gain_type Source Source_priority Confirmed_by]
      summary[:rows].each do |r|
        csv << [r[:date], r[:description], r[:asset_class], r[:amount], r[:gain_type], r[:source], r[:source_priority], Array(r[:confirmed_by]).join('|')]
      end
      csv << []
      csv << ['Canonical total sells (active)', summary[:total_sell_amount]]
      csv << ['Superseded total sells (audit)', summary[:superseded_sell_amount]]
      csv << ['Est. STCG (heuristic)', summary[:estimated_stcg]]
      csv << ['Est. LTCG (heuristic)', summary[:estimated_ltcg]]
      if summary[:document_stcg].to_f.positive? || summary[:document_ltcg].to_f.positive?
        csv << ['From tax docs STCG', summary[:document_stcg]]
        csv << ['From tax docs LTCG', summary[:document_ltcg]]
      end
    end
  end

  private

  def build_summary
    # Scope to ACTIVE rows only — superseded sells (e.g. broker_csv
    # rows confirmed by a later tax doc) are excluded from totals but
    # remain audit-queryable via the .superseded scope.
    fy_txs = @user.investment_transactions.for_fy(@fy)
    sells = fy_txs.active.where(kind: %w[sell transfer_out maturity])
    buys  = fy_txs.active.where(kind: %w[buy transfer_in])
    superseded_sells = fy_txs.superseded.where(kind: %w[sell transfer_out maturity])

    rows = sells.includes(:investment_holding).map do |tx|
      {
        date: tx.date,
        description: tx.description || tx.investment_holding&.name,
        asset_class: tx.asset_class,
        amount: tx.amount.to_f,
        gain_type: infer_gain_type(tx),
        source: tx.source,
        source_priority: tx.source_priority.to_i,
        confirmed_by: Array(tx.confirmed_by),
      }
    end

    doc_totals = tax_document_totals
    canonical = canonical_capital_gains(rows: rows, doc_totals: doc_totals)

    {
      financial_year_start: @fy,
      financial_year_label: FinancialYear.label(@fy),
      rows: rows,
      total_sell_amount: sells.sum(:amount).to_f,
      total_buy_amount: buys.sum(:amount).to_f,
      superseded_sell_amount: superseded_sells.sum(:amount).to_f,
      estimated_stcg: rows.select { |r| r[:gain_type] == 'STCG' }.sum { |r| r[:amount] },
      estimated_ltcg: rows.select { |r| r[:gain_type] == 'LTCG' }.sum { |r| r[:amount] },
      document_stcg: doc_totals[:stcg],
      document_ltcg: doc_totals[:ltcg],
      from_tax_documents: doc_totals[:sources],
      canonical_stcg: canonical[:stcg],
      canonical_ltcg: canonical[:ltcg],
      canonical_source: canonical[:source],
      source_breakdown: source_breakdown(rows),
    }
  end

  # Picks the figure to display as "the answer" in the UI's top stat
  # card. Priority-90 tax-doc figures (audited, signed) win over our
  # heuristic. The UI shows both side-by-side so the user can audit.
  def canonical_capital_gains(rows:, doc_totals:)
    if (doc_totals[:stcg].to_f + doc_totals[:ltcg].to_f).positive?
      return { stcg: doc_totals[:stcg], ltcg: doc_totals[:ltcg], source: 'tax_doc' }
    end

    stcg = rows.select { |r| r[:gain_type] == 'STCG' }.sum { |r| r[:amount] }
    ltcg = rows.select { |r| r[:gain_type] == 'LTCG' }.sum { |r| r[:amount] }
    { stcg: stcg, ltcg: ltcg, source: 'heuristic' }
  end

  # Counts of canonical sells per source — used by the UI to show
  # "8 of 12 sells confirmed by tax doc" badges.
  def source_breakdown(rows)
    rows.group_by { |r| r[:source] }.transform_values(&:count)
  end

  def tax_document_totals
    stcg = 0.0
    ltcg = 0.0
    sources = []

    %w[broker_pl mf_cg].each do |type|
      doc = @user.itr_tax_documents.find_by(financial_year_start: @fy, document_type: type)
      next unless doc&.extracted?

      data = doc.effective_data
      stcg += data['stcg'].to_f
      ltcg += data['ltcg'].to_f
      sources << ItrTaxDocument.label_for(type)
    end

    { stcg: stcg, ltcg: ltcg, sources: sources }
  end

  def infer_gain_type(tx)
    return 'STCG' if STCG_ASSET_CLASSES.include?(tx.asset_class)
    return 'LTCG' if LTCG_DEFAULT_ASSET_CLASSES.include?(tx.asset_class)

    'Review'
  end
end
