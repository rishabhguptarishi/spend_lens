# frozen_string_literal: true

class InvestmentSuggestionAcceptorService
  def initialize(user, suggestion)
    @user = user
    @suggestion = suggestion
  end

  def call
    tx = @suggestion.source_transaction
    account = find_or_create_account
    holding = find_or_create_holding(account, tx)

    inv_tx = @user.investment_transactions.create!(
      investment_account: account,
      investment_holding: holding,
      source_transaction: tx,
      date: tx.date,
      kind: @suggestion.suggested_kind,
      amount: tx.amount.to_f.abs,
      description: tx.description,
      source: 'bank_detect',
      asset_class: @suggestion.suggested_asset_class,
      financial_year_start: FinancialYear.start_year_for(tx.date)
    )

    update_holding_from_transaction(holding, inv_tx)
    @suggestion.update!(status: 'accepted')
    inv_tx
  end

  private

  def find_or_create_account
    name = @suggestion.suggested_account_name.presence || 'Investments'
    kind = infer_account_kind
    @user.investment_accounts.find_or_create_by!(name: name) do |a|
      a.provider = name
      a.account_kind = kind
    end
  end

  def infer_account_kind
    case @suggestion.suggested_asset_class
    when 'mutual_fund' then 'mf_platform'
    when 'stock' then 'broker'
    when 'fd', 'rd' then 'fd'
    when 'ppf' then 'ppf'
    when 'nps' then 'nps'
    when 'crypto' then 'crypto'
    else 'other'
    end
  end

  def find_or_create_holding(account, tx)
    label = tx.description.to_s.strip[0..100].presence || 'Holding'
    folio = extract_folio(tx.description)
    asset_class = @suggestion.suggested_asset_class

    # Folio-first match wins: lets accepted suggestions attach to a
    # canonical holding StatementParsing::PortfolioExtractor created from
    # the FD/PPF passbook, even when the suggestion description ("Trf to
    # PPF 000418336506") differs from the holding name ("ICICI PPF
    # 000418336506").
    if folio.present?
      existing = @user.investment_holdings.find_by(folio: folio, asset_class: asset_class)
      return existing if existing
    end

    # Fall back to name-based find-or-create — preserves the long-standing
    # behaviour where two transactions with identical descriptions (e.g.
    # repeated "GROWW ICCL" SIPs) collapse onto a single holding.
    @user.investment_holdings.find_or_create_by!(
      investment_account: account,
      asset_class: asset_class,
      name: label,
    ) do |h|
      h.folio = folio
    end
  end

  # Pulls a stable holding identifier (PPF account number, FD/RD deposit
  # number) out of common Indian-bank description formats so that an
  # accepted "Trf to PPF 000418336506" suggestion attaches to the canonical
  # holding StatementParsing::PortfolioExtractor already created from the
  # statement's summary block, rather than forking a parallel holding per
  # contribution.
  def extract_folio(description)
    desc = description.to_s
    return nil if desc.blank?

    if (m = desc.match(/Trf\s+to\s+PPF\s+(\d{6,})/i)); return m[1]; end
    if (m = desc.match(/TRF\s+TO\s+FD\s+(?:no\.?\s+)?(\d{6,})/i)); return m[1]; end
    if (m = desc.match(/(?:To|TRF\s+TO)\s+RD\s+(?:Ac\s+no\s+)?(\d{6,})/i)); return m[1]; end
    if (m = desc.match(/NPS\s+(?:Tier[- ]?[I]+\s+)?(?:A\/c\s+)?(\d{6,})/i)); return m[1]; end

    nil
  end

  def update_holding_from_transaction(holding, inv_tx)
    amt = inv_tx.amount.to_f
    case inv_tx.kind
    when 'buy', 'contribution', 'sip', 'transfer_in'
      holding.invested_amount = holding.invested_amount.to_f + amt
      holding.units = holding.units.to_f + inv_tx.units.to_f if inv_tx.units.present?
    when 'sell', 'transfer_out', 'maturity'
      holding.invested_amount = [holding.invested_amount.to_f - amt, 0].max
    end
    holding.save!
  end
end
