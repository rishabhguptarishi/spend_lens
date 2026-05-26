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

        if skip_duplicates && duplicate?(
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
          financial_year_start: fy
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
    @user.investment_holdings.find_or_create_by!(
      investment_account: account,
      name: label,
      asset_class: asset
    ) do |h|
      h.symbol = raw['symbol']
    end
  end
end
