# frozen_string_literal: true

# Scans bank transactions and creates pending investment suggestions.
#
# Each rule may specify an optional :kind_credit override — when the
# matched bank transaction is a CREDIT (money returning to savings) we
# use that instead of the default :kind. This is essential for things
# like MOB-TD where a debit creates an FD ('buy') and a credit closes
# it ('maturity'), or FRSB where debit = subscribe, credit = redeem.
class InvestmentDetectionService
  RULES = [
    # =================================================================
    # Stock brokers / equity platforms
    # =================================================================
    { pattern: /zerodha|kite|groww|angel\s*one|upstox|hdfc\s*sec|icici\s*direct|kotak\s*sec|axisdirect|sharekhan|fivepaisa|5paisa|motilal\s*oswal|indmoney|ind\s*money|paytm\s*money/i,
      asset_class: 'stock', kind: 'buy', kind_credit: 'sell',
      account_name: 'Broker account', account_kind: 'broker' },

    # =================================================================
    # Mutual funds
    # =================================================================
    # Aggregator / registrar platforms
    { pattern: /cams|kfintech|mfcentral|mf\s*central/i,
      asset_class: 'mutual_fund', kind: 'buy', kind_credit: 'sell',
      account_name: 'Mutual funds', account_kind: 'mf_platform' },

    # AMC names printed directly in the SIP description. Bank statements
    # truncate scheme names (e.g. "Canara Robeco E/.../ETGP" or "MIRAE
    # ASSET ELS/.../TSRG") so we anchor on the AMC token only.
    { pattern: /\b(?:canara\s+robeco|mirae\s+asset|nippon\s+(?:life|india)|sbi\s+(?:mf|mutual\s+fund)|hdfc\s+(?:mf|mutual\s+fund)|icici\s+pru|axis\s+(?:mf|small\s+cap|mid\s+cap|bluechip)|kotak\s+(?:mf|mutual\s+fund)|uti\s+(?:mf|mutual\s+fund)|parag\s+parikh|quant\s+(?:mf|small\s+cap|tax)|dsp\s+(?:mf|mutual\s+fund)|tata\s+(?:mf|mutual\s+fund)|aditya\s+birla\s+(?:mf|sun\s+life))\b/i,
      asset_class: 'mutual_fund', kind: 'sip', kind_credit: 'sell',
      account_name: 'Mutual fund SIPs', account_kind: 'mf_platform' },

    # =================================================================
    # Government / sovereign instruments
    # =================================================================
    # RBI Floating Rate Savings Bond — 7.15% sovereign retail bond.
    # Debit = subscription, credit = redemption / interest payout.
    { pattern: /\bFRSB\b/i,
      asset_class: 'bond', kind: 'buy', kind_credit: 'maturity',
      account_name: 'RBI Floating Rate Savings Bond', account_kind: 'other' },

    # =================================================================
    # Fixed / recurring deposits (bank-internal)
    # =================================================================
    # Mobile-banking term deposit. Each ref number is a distinct FD, so
    # the acceptor will create a holding per row (which is correct — each
    # MOB-TD is a separate fixed deposit with its own maturity date).
    { pattern: /\bMOB[-\s]?TD\b/i,
      asset_class: 'fd', kind: 'buy', kind_credit: 'maturity',
      account_name: 'Fixed deposits', account_kind: 'fd' },
    { pattern: /\bMOB[-\s]?FD\b/i,
      asset_class: 'fd', kind: 'buy', kind_credit: 'maturity',
      account_name: 'Fixed deposits', account_kind: 'fd' },
    { pattern: /\bMOB[-\s]?RD\b/i,
      asset_class: 'rd', kind: 'sip', kind_credit: 'maturity',
      account_name: 'Recurring deposits', account_kind: 'fd' },

    # Auto / reverse sweeps between SB and linked FD
    { pattern: /\bAUTOSWEEP\b/i,
      asset_class: 'fd', kind: 'buy', kind_credit: 'maturity',
      account_name: 'Sweep-in FD', account_kind: 'fd' },
    { pattern: /\bREV\s+SWEEP\b/i,
      asset_class: 'fd', kind: 'maturity', kind_credit: 'buy',
      account_name: 'Sweep-in FD', account_kind: 'fd' },
    { pattern: /\bSWEEP\s+TRF\b/i,
      asset_class: 'fd', kind: 'buy', kind_credit: 'maturity',
      account_name: 'Sweep-in FD', account_kind: 'fd' },

    # ICICI consolidated-statement FD principal funding. Phrased as
    # "TRF TO FD no. 153913018495" or "TRF TO FD 153925003301". The folio
    # (deposit number) is what InvestmentSuggestionAcceptorService uses to
    # link the contribution back to the canonical holding the
    # PortfolioExtractor already created from the FD passbook table.
    { pattern: /\bTRF\s+TO\s+FD\b/i,
      asset_class: 'fd', kind: 'buy', kind_credit: 'maturity',
      account_name: 'Fixed deposits', account_kind: 'fd' },

    # ICICI RD contributions: "To RD Ac no 153925003301" or "Dr Tran For
    # Funding A/c 153925003301" (RD account funding via mobile/net banking).
    { pattern: /\bTo\s+RD\s+Ac\s+no\b|\bDr\s+Tran\s+For\s+Funding\s+A\/c\b/i,
      asset_class: 'rd', kind: 'contribution', kind_credit: 'maturity',
      account_name: 'Recurring deposits', account_kind: 'fd' },

    # Interest credited on existing FD/RD — separate semantics from the
    # principal flows above. Interest is an income event regardless of
    # direction (rare debit cases would be a reversal): we set both kind
    # and kind_credit to 'interest' so resolve_kind never falls through
    # to a misleading default if the rule ever matches an unexpected sign.
    { pattern: /\bfd\s*int|fixed\s*deposit|term\s*deposit|rd\s*int|recurring\s*deposit/i,
      asset_class: 'fd', kind: 'interest', kind_credit: 'interest',
      account_name: 'Fixed deposit', account_kind: 'fd' },

    # =================================================================
    # Retirement / long-lock products
    # =================================================================
    # Contributions on debit; treat unusual NPS/PPF *credits* (rare —
    # typically withdrawals at maturity or partial PPF withdrawals) as
    # 'maturity' so we don't mis-stamp a withdrawal as a contribution.
    { pattern: /\bnps\b|nsdl\s*nps|protean\s*nps/i,
      asset_class: 'nps', kind: 'contribution', kind_credit: 'maturity',
      account_name: 'NPS', account_kind: 'nps' },
    { pattern: /\bppf\b|public\s*provident/i,
      asset_class: 'ppf', kind: 'contribution', kind_credit: 'maturity',
      account_name: 'PPF', account_kind: 'ppf' },

    # =================================================================
    # Income from existing positions
    # =================================================================
    # NACH credits from listed companies (typically dividends). Dividend
    # is by definition a credit, but stamp kind_credit explicitly so the
    # rule's intent is unambiguous (and a stray debit match wouldn't get
    # silently coerced to a different semantic).
    { pattern: /\bACH[-\s]CR\b/i,
      asset_class: 'stock', kind: 'dividend', kind_credit: 'dividend',
      account_name: 'Dividends', account_kind: 'broker' },
    { pattern: /dividend|div\s*cr/i,
      asset_class: 'stock', kind: 'dividend', kind_credit: 'dividend',
      account_name: 'Dividends', account_kind: 'broker' },

    # =================================================================
    # Crypto
    # =================================================================
    { pattern: /coinbase|binance|wazirx|coindcx|crypto/i,
      asset_class: 'crypto', kind: 'buy', kind_credit: 'sell',
      account_name: 'Crypto', account_kind: 'crypto' },
  ].freeze

  def initialize(user)
    @user = user
  end

  def scan_transactions!(transaction_ids: nil)
    scope = bank_transactions
    scope = scope.where(id: transaction_ids) if transaction_ids.present?

    created = 0
    scope.find_each do |tx|
      next if InvestmentSuggestion.exists?(transaction_id: tx.id)

      match = match_rule(tx)
      next unless match

      InvestmentSuggestion.create!(
        user: @user,
        source_transaction: tx,
        suggested_asset_class: match[:asset_class],
        suggested_kind: resolve_kind(match, tx),
        suggested_account_name: match[:account_name],
        status: 'pending'
      )
      created += 1
    end
    created
  end

  # Picks :kind_credit when the matched bank transaction is a CREDIT
  # (e.g. FD maturing back into savings), otherwise the default :kind.
  # Falls back to :kind whenever :kind_credit isn't set, so legacy rules
  # without the override behave exactly as before.
  def resolve_kind(rule, tx)
    return rule[:kind] unless tx.transaction_type.to_s == 'credit'

    rule[:kind_credit].presence || rule[:kind]
  end

  def self.rules_for(user)
    custom = user.user_investment_detection_rules.ordered.map(&:to_detection_rule)
    custom + RULES
  end

  def self.match_rule(tx, user: nil)
    text = [tx.description, tx.merchant].compact.join(' ')
    return nil if text.blank?

    rules = user ? rules_for(user) : RULES
    rules.each do |rule|
      return rule if text.match?(rule[:pattern])
    end
    nil
  end

  private

  def bank_transactions
    Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: @user.id })
      .where('transactions.date >= ?', 2.years.ago)
  end

  def match_rule(tx)
    self.class.match_rule(tx, user: @user)
  end
end
