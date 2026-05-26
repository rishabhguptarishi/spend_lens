# frozen_string_literal: true

module StatementParsing
  # Extracts portfolio items (PPF / FD / RD / NPS) from consolidated bank
  # statements that print holdings alongside transaction history. Used
  # primarily for ICICI consolidated statements today; safe no-op for any
  # statement that doesn't carry structured holding tables.
  #
  # Persistence model:
  # - One canonical InvestmentAccount per provider+kind ("ICICI Bank — PPF",
  #   "ICICI Bank — Fixed Deposits", "ICICI Bank — Recurring Deposits").
  # - One InvestmentHolding per folio/deposit number. `folio` is the key
  #   that dedupes against future statement uploads AND against suggestion
  #   acceptance — InvestmentSuggestionAcceptorService is updated to look
  #   up by folio first so a savings-side "Trf to PPF 000418336506" debit
  #   that's accepted later links to this extractor's PPF holding instead
  #   of forking a duplicate.
  class PortfolioExtractor
    Result = Struct.new(:holdings_created, :holdings_updated, :transactions_created, keyword_init: true) do
      def empty?
        holdings_created.zero? && holdings_updated.zero? && transactions_created.zero?
      end
    end

    # FD/RD table row example:
    # 153913018495     07-02-2026         50,000.00    6.50             60 Mths         69,021.00       07-02-2031         50,489.00     Registered
    #
    # We anchor on:
    #   deposit_no (alphanumeric, >=9 chars to avoid matching column header noise)
    #   open_date  (dd-mm-yyyy)
    #   dep_amt    (Indian-comma money)
    DEPOSIT_ROW_RE = /^\s*(\d{9,})\s+(\d{2}-\d{2}-\d{4})\s+([\d,]+\.\d{2})\s+([\d.]+)\s+(.*?)\s+([\d,]+\.\d{2})\s+(\d{2}-\d{2}-\d{4})\s+([\d,]+\.\d{2})/

    # PPF balance row from the account summary block:
    # PPF A/c 000418336506                         3,83,025.00                                 0.00                    3,83,025.00     Registered
    PPF_SUMMARY_RE = /\bPPF\s+A\/c\s+(\d{6,})\s+([\d,]+\.\d{2})/i

    # NPS rows (less standardized across banks; supports a handful of phrasings)
    NPS_SUMMARY_RE = /\bNPS\s+(?:Tier[- ]?[I]+\s+)?(?:A\/c\s+)?(\d{6,})\s+([\d,]+\.\d{2})/i

    def initialize(statement:, content:, user: nil)
      @statement = statement
      @content = content.to_s
      @user = user || statement&.bank_account&.user
    end

    def call
      return empty_result unless @user
      return empty_result unless icici_statement?

      created = updated = txs_created = 0

      ActiveRecord::Base.transaction do
        ppf_results = extract_ppf
        created += ppf_results[:created]
        updated += ppf_results[:updated]

        fd_results = extract_deposits(:fd)
        created += fd_results[:created]
        updated += fd_results[:updated]
        txs_created += fd_results[:transactions_created]

        rd_results = extract_deposits(:rd)
        created += rd_results[:created]
        updated += rd_results[:updated]
        txs_created += rd_results[:transactions_created]
      end

      Result.new(
        holdings_created: created,
        holdings_updated: updated,
        transactions_created: txs_created,
      )
    rescue => e
      Rails.logger.error "StatementParsing::PortfolioExtractor failed: #{e.class}: #{e.message}"
      empty_result
    end

    private

    def empty_result
      Result.new(holdings_created: 0, holdings_updated: 0, transactions_created: 0)
    end

    def icici_statement?
      head = @content.lines.first(80).join("\n")
      head.match?(/\b(?:ICICI\s+Bank|icicibank\.com|ICIC0\d{4,})\b/i)
    end

    # PPF semantics differ from FD/RD: the passbook balance bundles
    # principal + accrued interest, so it is NOT a cost basis. Bank-detect
    # also picks up "Trf to PPF <folio>" debits and adds them to
    # invested_amount on accept — if we ALSO overwrite invested_amount with
    # the passbook balance on every re-upload, we either erase the user's
    # contribution history or (worse) end up summing balance + contributions
    # for the same money. Contract from Phase 0 onward:
    #
    #   - balance lives in metadata.last_seen_balance, updated every upload
    #   - invested_amount is seeded from balance ONLY at create time so a
    #     brand-new PPF holding doesn't render as ₹0 in the UI
    #   - subsequent uploads NEVER overwrite invested_amount; it accrues
    #     from accepted suggestions / manual entries
    #
    # Phase 1 introduces a proper Position layer with source-priority
    # reconciliation; this is the bridge until then.
    def extract_ppf
      match = @content.match(PPF_SUMMARY_RE)
      return { created: 0, updated: 0 } unless match

      folio = match[1]
      balance = match[2].gsub(',', '').to_f
      return { created: 0, updated: 0 } if balance <= 0

      account = find_or_create_account(provider: 'ICICI Bank', kind: 'ppf', label: 'PPF')
      holding = @user.investment_holdings.find_by(folio: folio, asset_class: 'ppf')

      if holding
        holding.update!(
          investment_account: account,
          name: "ICICI PPF #{folio}",
          metadata: merge_metadata(holding.metadata, last_seen_balance: balance, source: 'icici_statement'),
        )
        { created: 0, updated: 1 }
      else
        @user.investment_holdings.create!(
          investment_account: account,
          asset_class: 'ppf',
          name: "ICICI PPF #{folio}",
          folio: folio,
          invested_amount: balance,
          metadata: { last_seen_balance: balance, source: 'icici_statement' },
        )
        { created: 1, updated: 0 }
      end
    end

    # Parses FD or RD blocks. The two tables share an identical layout and
    # are differentiated by their preceding heading ("FIXED DEPOSITS" vs
    # "RECURRING DEPOSITS"). We slice the document on those headings and
    # apply DEPOSIT_ROW_RE row-by-row.
    def extract_deposits(kind)
      heading = kind == :fd ? 'FIXED DEPOSITS' : 'RECURRING DEPOSITS'
      asset_class = kind.to_s
      account_label = kind == :fd ? 'Fixed Deposits' : 'Recurring Deposits'
      txn_kind = 'buy'

      block = extract_block(heading)
      return { created: 0, updated: 0, transactions_created: 0 } if block.blank?

      account = find_or_create_account(provider: 'ICICI Bank', kind: 'fd', label: account_label)
      created = updated = txs_created = 0

      block.each_line do |line|
        match = line.match(DEPOSIT_ROW_RE)
        next unless match

        deposit_no = match[1]
        open_date_str = match[2]
        dep_amt = match[3].gsub(',', '').to_f
        roi = match[4].to_f
        maturity_amt = match[6].gsub(',', '').to_f
        maturity_date_str = match[7]
        balance = match[8].gsub(',', '').to_f

        open_date = parse_date(open_date_str)
        maturity_date = parse_date(maturity_date_str)
        next if dep_amt <= 0 || open_date.nil?

        holding = @user.investment_holdings.find_by(folio: deposit_no, asset_class: asset_class)

        attrs = {
          investment_account: account,
          name: "ICICI #{kind == :fd ? 'FD' : 'RD'} #{deposit_no}",
          asset_class: asset_class,
          folio: deposit_no,
          invested_amount: dep_amt,
          metadata: {
            source: 'icici_statement',
            interest_rate: roi,
            maturity_amount: maturity_amt,
            maturity_date: maturity_date_str,
            open_date: open_date_str,
            current_balance: balance,
          },
        }

        if holding
          holding.update!(attrs)
          updated += 1
        else
          holding = @user.investment_holdings.create!(attrs)
          created += 1
        end

        next unless @user.investment_transactions.where(
          investment_holding_id: holding.id,
          source: 'bank_statement',
          kind: 'buy',
          date: open_date,
        ).none?

        @user.investment_transactions.create!(
          investment_account: account,
          investment_holding: holding,
          date: open_date,
          kind: txn_kind,
          amount: dep_amt,
          description: "Opened #{kind == :fd ? 'FD' : 'RD'} #{deposit_no} @ #{roi}%",
          source: 'bank_statement',
          asset_class: asset_class,
          financial_year_start: FinancialYear.start_year_for(open_date),
        )
        txs_created += 1
      end

      { created: created, updated: updated, transactions_created: txs_created }
    end

    # Slice the document between a section heading and the next sentinel
    # (next section heading or "Statement of Transactions" marker). We
    # MUST anchor on the "- INR" suffix that follows real ICICI passbook
    # section titles ("FIXED DEPOSITS - INR", "RECURRING DEPOSITS - INR")
    # because the substring "FIXED DEPOSITS" also occurs inside the
    # account-summary column header ("FIXED DEPOSITS (LINKED) BAL.(II)").
    # Without the anchor, extract_block returned the entire account
    # summary block as if it were the FD passbook.
    def extract_block(heading)
      heading_re = /#{Regexp.escape(heading)}\s*-\s*INR\b/i
      heading_idx = @content.index(heading_re)
      return nil unless heading_idx

      tail = @content[heading_idx..]
      next_section_re = /Statement\s+of\s+Transactions|FIXED\s+DEPOSITS\s*-\s*INR|RECURRING\s+DEPOSITS\s*-\s*INR/i
      stop = tail.index(next_section_re, heading.length + 5) # past the current section's "- INR"
      stop ? tail[0...stop] : tail
    end

    def find_or_create_account(provider:, kind:, label:)
      name = "#{provider} \u2014 #{label}" # em-dash
      @user.investment_accounts.find_or_create_by!(name: name) do |a|
        a.provider = provider
        a.account_kind = kind
      end
    end

    def merge_metadata(existing, **incoming)
      base = existing.is_a?(Hash) ? existing.symbolize_keys : {}
      base.merge(incoming)
    end

    def parse_date(str)
      Date.strptime(str, '%d-%m-%Y')
    rescue ArgumentError
      nil
    end
  end
end
