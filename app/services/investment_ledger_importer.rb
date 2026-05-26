# frozen_string_literal: true

# Shared path for broker imports, tax doc sync, and batch imports.
class InvestmentLedgerImporter
  def initialize(user)
    @user = user
  end

  def import_rows(rows:, account:, financial_year_start:, source: 'broker_import', skip_duplicates: true)
    imported = 0

    ActiveRecord::Base.transaction do
      rows.each do |raw|
        h = raw.is_a?(Hash) ? raw.stringify_keys : raw
        next if h['selected'] == false

        date = Date.parse(h['date'].to_s)
        kind = h['kind'].presence || 'other'
        amount = h['amount'].to_f
        fy = h['financial_year_start'].presence || financial_year_start
        description = h['description'].presence || 'Import'

        next if amount <= 0

        external_id = Investments::ExternalIdComputer.call(
          source: source,
          provider: account.provider.presence || account.name,
          folio: h['folio'],
          isin: h['isin'].presence || h['symbol'],
          symbol: h['symbol'],
          date: date,
          units: h['units'],
          amount: amount,
          kind: kind,
          order_id: h['order_id'],
          trade_id: h['trade_id'],
          document_id: h['document_id'],
          row_index: h['row_index'],
          transaction_id: h['transaction_id'],
        )

        if external_id.present? && @user.investment_transactions.exists?(external_id: external_id)
          next
        end

        if skip_duplicates && external_id.blank? && duplicate?(
          account: account,
          date: date,
          kind: kind,
          amount: amount,
          description: description,
          financial_year_start: fy
        )
          next
        end

        holding = find_or_create_holding(account, h, description)
        @user.investment_transactions.create!(
          investment_account: account,
          investment_holding: holding,
          date: date,
          kind: kind,
          amount: amount,
          units: h['units'],
          description: description,
          asset_class: h['asset_class'].presence || 'other',
          source: source,
          financial_year_start: fy,
          external_id: external_id,
        )
        imported += 1
      end
    end

    imported
  end

  private

  def duplicate?(account:, date:, kind:, amount:, description:, financial_year_start:)
    @user.investment_transactions.exists?(
      investment_account: account,
      date: date,
      kind: kind,
      amount: amount,
      description: description,
      financial_year_start: financial_year_start
    )
  end

  def find_or_create_holding(account, raw, description)
    label = description.to_s[0..100]
    asset = raw['asset_class'].presence || 'other'

    # Prefer ISIN/identity-key-based lookup when we have enough metadata
    # so two parsers seeing the same security (e.g. CDSL CAS and a
    # broker CSV both reporting INE002A01018) collapse onto a single
    # InvestmentHolding rather than forking by description.
    identity_key = Investments::IdentityKeyComputer.from_attrs(
      asset_class: asset,
      isin: raw['isin'].presence || raw['symbol'],
      symbol: raw['symbol'],
      folio: raw['folio'],
      provider: account.provider.presence || account.name,
      amc: raw['amc'] || account.provider,
    )

    if identity_key.present?
      existing = @user.investment_holdings.find_by(identity_key: identity_key)
      return existing if existing
    end

    @user.investment_holdings.find_or_create_by!(
      investment_account: account,
      name: label,
      asset_class: asset
    ) do |h|
      h.symbol = raw['symbol']
      h.folio  = raw['folio']
      h.identity_key = identity_key
      h.metadata = (h.metadata || {}).merge(amc: raw['amc']).compact if raw['amc'].present?
    end
  end
end
