# frozen_string_literal: true

class CapitalGainsSummaryService
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
      csv << %w[Date Description Asset_class Amount Gain_type Source]
      summary[:rows].each do |r|
        csv << [r[:date], r[:description], r[:asset_class], r[:amount], r[:gain_type], r[:source]]
      end
      csv << []
      csv << ['Total sells', summary[:total_sell_amount]]
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
    sells = @user.investment_transactions.for_fy(@fy).where(kind: %w[sell transfer_out maturity])
    buys = @user.investment_transactions.for_fy(@fy).where(kind: %w[buy transfer_in])

    rows = sells.includes(:investment_holding).map do |tx|
      {
        date: tx.date,
        description: tx.description || tx.investment_holding&.name,
        asset_class: tx.asset_class,
        amount: tx.amount.to_f,
        gain_type: infer_gain_type(tx),
        source: tx.source,
      }
    end

    doc_totals = tax_document_totals

    {
      financial_year_start: @fy,
      financial_year_label: FinancialYear.label(@fy),
      rows: rows,
      total_sell_amount: sells.sum(:amount).to_f,
      total_buy_amount: buys.sum(:amount).to_f,
      estimated_stcg: rows.select { |r| r[:gain_type] == 'STCG' }.sum { |r| r[:amount] },
      estimated_ltcg: rows.select { |r| r[:gain_type] == 'LTCG' }.sum { |r| r[:amount] },
      document_stcg: doc_totals[:stcg],
      document_ltcg: doc_totals[:ltcg],
      from_tax_documents: doc_totals[:sources],
    }
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
    # Without purchase date linkage, equity/MF defaults to STCG flag for review
    case tx.asset_class
    when 'mutual_fund', 'stock' then 'STCG' # user should confirm with broker P&L
    when 'real_estate' then 'LTCG'
    else 'Review'
    end
  end
end
