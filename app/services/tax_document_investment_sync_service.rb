# frozen_string_literal: true

# Applies confirmed broker P&L / MF CG data into investment ledger.
class TaxDocumentInvestmentSyncService
  def initialize(user, document)
    @user = user
    @document = document
    @fy = document.financial_year_start
  end

  def call
    return 0 unless @document.document_type.in?(%w[broker_pl mf_cg])
    return 0 if @document.ledger_synced_at.present?

    data = @document.effective_data
    rows = normalize_rows(data)
    return 0 if rows.empty?

    account = find_account
    imported = InvestmentLedgerImporter.new(@user).import_rows(
      rows: rows,
      account: account,
      financial_year_start: @fy,
      source: 'broker_import',
      skip_duplicates: true
    )

    @document.update!(ledger_synced_at: Time.current) if imported.positive? || rows.any?
    imported
  end

  def self.reset_sync!(document)
    document.update!(ledger_synced_at: nil)
  end

  private

  def normalize_rows(data)
    txs = data['transactions'] || data['rows'] || []
    return [] unless txs.is_a?(Array)

    asset = @document.document_type == 'mf_cg' ? 'mutual_fund' : 'stock'

    txs.filter_map do |tx|
      h = tx.is_a?(Hash) ? tx.stringify_keys : {}
      date = h['date']
      amount = h['amount'].to_f
      next if date.blank? || amount <= 0

      {
        'date' => date,
        'kind' => h['kind'].presence || 'sell',
        'amount' => amount,
        'description' => h['description'].presence || h['symbol'].presence || 'Tax document',
        'asset_class' => h['asset_class'].presence || asset,
        'financial_year_start' => h['financial_year_start'] || FinancialYear.start_year_for(Date.parse(date.to_s)),
        'symbol' => h['symbol'],
      }
    end
  end

  def find_account
    name = @document.document_type == 'mf_cg' ? 'Mutual funds (tax)' : 'Broker (tax P&L)'
    kind = @document.document_type == 'mf_cg' ? 'mf_platform' : 'broker'
    @user.investment_accounts.find_or_create_by!(name: name) do |a|
      a.account_kind = kind
      a.provider = name
    end
  end
end
