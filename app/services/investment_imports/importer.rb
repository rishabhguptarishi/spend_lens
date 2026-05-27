# frozen_string_literal: true

module InvestmentImports
  class Importer
    # Canonical user-facing account label per batch source. Centralised so
    # parsers and the importer can't drift on capitalisation (e.g. CDSL CAS
    # rows used to emit "Mutual Funds (CAS)" while this map said
    # "Mutual funds (CAS)" — two distinct accounts for one logical bucket).
    MUTUAL_FUNDS_CAS_ACCOUNT_NAME = 'Mutual Funds (CAS)'

    DEFAULT_ACCOUNT_NAMES = {
      'zerodha'      => 'Zerodha',
      'groww'        => 'Groww',
      'hdfc_sec'     => 'HDFC Securities',
      'mf_cas'       => MUTUAL_FUNDS_CAS_ACCOUNT_NAME,
      'cdsl_cas'     => 'CDSL CAS',
      'nsdl_cas'     => 'NSDL CAS',
      'epf_passbook' => 'EPF Passbook',
      'nps_statement' => 'NPS',
      'amc_direct'   => MUTUAL_FUNDS_CAS_ACCOUNT_NAME,
      'cams_cas'     => MUTUAL_FUNDS_CAS_ACCOUNT_NAME,
      'kfintech_cas' => MUTUAL_FUNDS_CAS_ACCOUNT_NAME,
      'generic_csv'  => 'Imported portfolio',
    }.freeze

    # Which `InvestmentTransaction#source` to stamp per batch type. Keeps the
    # downstream taxonomy (and the Capital Gains / reconciler logic) honest:
    # MF CAS data is "mf_cas", CDSL is "cdsl_cas", broker CSVs are
    # "broker_import". Anything unmapped defaults to "broker_import" for
    # backward compatibility.
    TXN_SOURCE_BY_BATCH = {
      'mf_cas'       => 'mf_cas',
      'cams_cas'     => 'mf_cas',
      'kfintech_cas' => 'mf_cas',
      'cdsl_cas'     => 'cdsl_cas',
      'nsdl_cas'     => 'cdsl_cas',
      'epf_passbook' => 'epf_passbook',
      'nps_statement' => 'nps_statement',
      'amc_direct'   => 'amc_direct',
    }.freeze

    def initialize(user, batch)
      @user = user
      @batch = batch
    end

    def call(rows: nil)
      rows ||= @batch.preview_rows

      txn_source = TXN_SOURCE_BY_BATCH.fetch(@batch.source, 'broker_import')

      imported = if route_per_row?(rows)
                   import_with_per_row_accounts(rows, txn_source: txn_source)
                 else
                   account = find_or_create_account
                   InvestmentLedgerImporter.new(@user).import_rows(
                     rows: rows,
                     account: account,
                     financial_year_start: @batch.financial_year_start,
                     source: txn_source,
                     skip_duplicates: true
                   )
                 end

      # The ledger importer creates holdings with invested_amount=0; the
      # acceptor-service flow used to add per-transaction increments. For
      # batch CSV/PDF imports we close the loop here by recomputing each
      # holding's totals from its now-persisted transactions.
      InvestmentHolding.recompute_totals_for(@user) if imported.positive?

      @batch.update!(
        status: 'imported',
        metadata: @batch.metadata.merge('imported_count' => imported, 'imported_at' => Time.current.iso8601)
      )
      imported
    end

    private

    # CDSL CAS spans multiple brokers (one InvestmentAccount each) plus a
    # combined MF folios account. Other sources still use one account per batch.
    # We honour per-row `:account_hint` only when the user hasn't explicitly
    # pinned the whole batch to one account.
    def route_per_row?(rows)
      return false if @batch.investment_account_id.present?

      @batch.source == 'cdsl_cas' && rows.any? { |r| r.is_a?(Hash) && (r['account_hint'] || r[:account_hint]).present? }
    end

    def import_with_per_row_accounts(rows, txn_source:)
      ledger = InvestmentLedgerImporter.new(@user)
      imported = 0

      rows.group_by { |r| (r.is_a?(Hash) ? r['account_hint'] || r[:account_hint] : nil).to_s.presence || default_account_name }.each do |hint, hint_rows|
        account = find_or_create_account_for(hint)
        imported += ledger.import_rows(
          rows: hint_rows,
          account: account,
          financial_year_start: @batch.financial_year_start,
          source: txn_source,
          skip_duplicates: true
        )
      end

      imported
    end

    def find_or_create_account_for(name)
      kind = name.to_s.match?(/mutual\s*fund|MF/i) ? 'mf_platform' : 'broker'
      @user.investment_accounts.find_or_create_by!(name: name) do |a|
        a.account_kind = kind
        a.provider = name
      end
    end

    def find_or_create_account
      if @batch.investment_account_id.present?
        return @user.investment_accounts.find(@batch.investment_account_id)
      end

      name = default_account_name
      @user.investment_accounts.find_or_create_by!(name: name) do |a|
        a.account_kind = default_account_kind
        a.provider = name
      end
    end

    def default_account_name
      DEFAULT_ACCOUNT_NAMES[@batch.source] || 'Imported'
    end

    def default_account_kind
      case @batch.source
      when 'mf_cas', 'cams_cas', 'kfintech_cas', 'cdsl_cas', 'nsdl_cas', 'amc_direct'
        'mf_platform'
      when 'epf_passbook'
        'epf'
      when 'nps_statement'
        'nps'
      else
        'broker'
      end
    end
  end
end
