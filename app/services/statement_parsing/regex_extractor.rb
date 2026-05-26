# frozen_string_literal: true

module StatementParsing
  # Layer 2: Regex/structure-based extraction (returns hashes, does not save).
  class RegexExtractor
    # Strict money matcher: requires EITHER Indian-comma grouping (e.g.
    # "1,000", "1,00,000.00") OR a decimal point (e.g. "1000.00", "0.50").
    # Bare integers like "1955" (Axis "Init.Br" branch column) or
    # "133826853" (NACH transaction reference) intentionally DO NOT match,
    # because mistaking them for amounts was the root cause of every Axis
    # transaction parsing as ₹195 / ₹256 (the truncated branch codes).
    AMOUNT_RE = /\b(?:\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+\.\d{1,2})\b/

    # Section header in multi-account statements (ICICI consolidated, etc.).
    # Matches:
    #   "Statement of Transactions in Savings Account Number: 1234567"
    #   "Statement of Transactions in Account Number: 999999"  (PPF)
    #   "Statement of Transactions in Current Account Number: 8888888"
    SECTION_HEADER_RE = /Statement\s+of\s+Transactions\s+in\s+(.*?)\s*Account\s+Number\s*:\s*(\S+)/i

    # Section terminator. Matches the "TOTAL ... ... ..." summary row that
    # ICICI prints at the end of each account section. We treat it as
    # "stop reading transactions until the next section header".
    SECTION_TERMINATOR_RE = /^\s*TOTAL\s+/

    # B/F (Brought Forward) opening-balance row. Has only the balance
    # column populated, never a debit/credit amount. Easy to miscount as
    # a ₹2,79,887 mystery debit if not explicitly skipped.
    BROUGHT_FORWARD_RE = /^\s*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\s+B\/F\b/i

    def initialize(content:, format:)
      @content = content
      @format = format.to_sym
    end

    def call
      case @format
      when :csv then extract_csv
      when :pdf then extract_pdf
      else []
      end
    end

    private

    def extract_csv
      require 'csv'
      rows = CSV.parse(@content, headers: true, liberal_parsing: true)
      headers = rows.headers
      return [] if headers.blank?

      date_col = find_column(headers, %w[date transaction_date txn_date posting_date])
      return [] if date_col.blank?

      date_header = headers[date_col]
      desc_col = find_column(headers, %w[description particulars narrative memo])
      debit_col = find_column(headers, %w[debit withdrawal])
      credit_col = find_column(headers, %w[credit deposit])
      amount_col = find_column(headers, %w[amount balance amt transaction_amount])
      type_col = find_column(headers, %w[type transaction_type dr/cr])

      desc_header = desc_col ? headers[desc_col] : headers[1]
      amount_header = if amount_col
                        headers[amount_col]
                      elsif headers.length >= 4
                        last = headers.last.to_s.downcase
                        (last.include?('amount') || last.include?('amt')) ? headers.last : headers[2]
                      else
                        headers[2]
                      end
      type_header = type_col ? headers[type_col] : nil
      debit_header = debit_col ? headers[debit_col] : nil
      credit_header = credit_col ? headers[credit_col] : nil

      rows.filter_map do |row|
        next if row[date_header].to_s.strip.blank?

        description = row[desc_header]&.to_s&.strip
        amount, transaction_type = parse_csv_amount_and_type(
          row: row,
          debit_header: debit_header,
          credit_header: credit_header,
          amount_header: amount_header,
          type_header: type_header,
          description: description
        )
        next if amount.zero?

        {
          date: parse_date_flexible(row[date_header]),
          description: description,
          amount: amount.abs,
          transaction_type: transaction_type,
          source: 'regex',
        }
      rescue => e
        Rails.logger.warn "Regex CSV row skip: #{e.message}"
        nil
      end
    end

    def extract_pdf
      skip_patterns = /\b(A\/C Open Date|Account Status|From\s*:|To\s*:|Statement of account|Page No\.?|Closing Balance|Contents of this statement|Registered Office)\b/i
      tx_date_regex = /^\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\s+/
      tx_date_regex_alt = /\b(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{2,4})\b/i

      # Bank-specific layout detection. We support three discriminated layouts:
      #   :axis   — particulars wrap ABOVE the date row; uses balance arithmetic
      #   :icici  — multi-account sections; uses explicit DEPOSITS/WITHDRAWALS columns
      #   :other  — HDFC / SBI fall back to the generic balance-arithmetic path
      layout = detect_layout
      running_balance = detect_opening_balance

      results = []
      lines = @content.split("\n")
      current_tx = nil
      pending_prefix = []

      # Section tracking for multi-account statements. `in_spendable_section`
      # starts true so single-account statements (HDFC / Axis / SBI) parse
      # exactly as before — only flips off when we explicitly enter a non-
      # spendable section (PPF / loan / FD passbook block) in ICICI-style
      # consolidated statements.
      in_spendable_section = true
      deposits_col = nil
      withdrawals_col = nil

      lines.each do |line|
        next if line.blank?

        # Section header? Always processed regardless of current section.
        if (section = line.match(SECTION_HEADER_RE))
          # ICICI prints the column header right after the section title.
          # Reset column positions so we re-discover them on the next
          # "DATE ... DEPOSITS ... WITHDRAWALS ... BALANCE" line.
          deposits_col = nil
          withdrawals_col = nil
          in_spendable_section = spendable_section?(section[1])
          # Reset running balance — next section has its own B/F balance
          # which arrives in the BALANCE column of the B/F row.
          running_balance = nil
          # Commit any in-flight tx before the section break.
          results << build_pdf_tx(current_tx) if current_tx && current_tx[:amount].to_f >= 0.01
          current_tx = nil
          next
        end

        # Section terminator? Stop accumulating until next section header.
        if line.match?(SECTION_TERMINATOR_RE)
          results << build_pdf_tx(current_tx) if current_tx && current_tx[:amount].to_f >= 0.01
          current_tx = nil
          in_spendable_section = false # await next section header
          next
        end

        # Discover ICICI column positions from the table header row.
        if layout == :icici && deposits_col.nil? && line =~ /\bDEPOSITS\b.*\bWITHDRAWALS\b.*\bBALANCE\b/i
          deposits_col = line.index(/\bDEPOSITS\b/i)
          withdrawals_col = line.index(/\bWITHDRAWALS\b/i)
          next
        end

        next if line.match?(skip_patterns)
        next if line.strip.match?(/^\d+\s*$/)
        next if line.match?(BROUGHT_FORWARD_RE) # opening balance, not a txn

        # Skip everything inside non-spendable sections (PPF / loan / FD passbook).
        next unless in_spendable_section

        date_match = line.match(tx_date_regex) || line.match(tx_date_regex_alt)
        if date_match
          results << build_pdf_tx(current_tx) if current_tx && current_tx[:amount].to_f >= 0.01

          date_str = date_match[1]
          rest = line[date_match.end(0)..].to_s

          amount, balance, column_direction = extract_amounts_and_direction(
            line: line,
            rest: rest,
            layout: layout,
            deposits_col: deposits_col,
            withdrawals_col: withdrawals_col
          )

          prefix_text = (layout == :axis && pending_prefix.any?) ? pending_prefix.join(' ').strip : ''
          desc = clean_description(rest)
          if prefix_text.present?
            desc = "#{prefix_text} #{desc}".gsub(/\s+/, ' ').strip[0..200]
            pending_prefix.clear
          end

          tx_type = determine_tx_type(
            line: line,
            rest: "#{prefix_text} #{rest}",
            amount: amount,
            balance: balance,
            running_balance: running_balance,
            column_direction: column_direction,
          )

          if balance && running_balance && (balance - running_balance).abs.between?(amount * 0.99 - 0.01, amount * 1.01 + 0.01)
            running_balance = balance
          elsif balance && running_balance.nil?
            running_balance = balance
          end

          current_tx = {
            date: parse_date_flexible(date_str),
            description: desc.presence || 'Unknown',
            amount: amount,
            transaction_type: tx_type,
          }
        elsif current_tx && line.strip.length.positive? && !line.match?(/^\s*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/)
          if layout == :axis
            # Buffer wrap-content for the NEXT date row. (Axis prints the
            # overflow line above its owning date — appending to the
            # previous tx instead is exactly how every SIP description
            # ended up cross-contaminated with "Int.Pd:..." text.)
            pending_prefix << line.strip if pending_prefix.size < 3
          else
            current_tx[:description] = "#{current_tx[:description]} #{line.strip}"[0..200]
          end
        end
      end

      results << build_pdf_tx(current_tx) if current_tx && current_tx[:amount].to_f >= 0.01
      results.compact
    end

    # Discriminates layout up-front. Used to route line-wrapping and
    # column-extraction heuristics. Returns :axis, :icici, or :other.
    def detect_layout
      return :axis if axis_statement?
      return :icici if icici_statement?

      :other
    end

    def axis_statement?
      head = @content.to_s.lines.first(60).join("\n")
      head.match?(/\b(?:Axis\s+Bank|Statement\s+of\s+Axis|UTIB\d{4,})\b/i)
    end

    # ICICI's tell: the bank's IFSC prefix (ICIC0XXXXXX), the icicibank.com
    # URL it stamps on every statement, or the "Statement of Transactions in
    # ... Account Number" header that no other Indian bank uses verbatim.
    def icici_statement?
      head = @content.to_s.lines.first(80).join("\n")
      head.match?(/\b(?:ICICI\s+Bank|icicibank\.com|ICIC0\d{4,})\b/i)
    end

    # A section is "spendable" (= bank account that holds liquid money the
    # user actually transacts with) when the section title contains
    # "Savings", "Current", or "Credit Card". Bare "Account" with no
    # qualifier on ICICI consolidated statements always denotes PPF / FD
    # passbook blocks — money is committed there, not spendable.
    def spendable_section?(title)
      title.to_s.match?(/\b(savings|current|credit\s*card|cc)\b/i)
    end

    def detect_opening_balance
      m = @content.to_s.match(/OPENING\s+BALANCE[^\d]+([\d,]+\.\d{1,2})/i)
      return nil unless m

      m[1].gsub(',', '').to_f
    end

    # Extracts the transaction amount, running balance, and (for ICICI
    # statements) the direction implied by which column the amount sits
    # in. Returns [amount, balance, column_direction|nil].
    def extract_amounts_and_direction(line:, rest:, layout:, deposits_col:, withdrawals_col:)
      amounts = rest.scan(AMOUNT_RE).map { |a| a.gsub(',', '').to_f }
      amounts = amounts.select { |a| a >= 0.01 && a < 1e10 }

      amount = 0
      balance = nil
      if amounts.size >= 2
        amount = amounts[-2]
        balance = amounts[-1]
      elsif amounts.size == 1
        amount = amounts[0]
      end

      column_direction = nil
      if layout == :icici && deposits_col && withdrawals_col && amount.positive?
        # Use the position of the first qualifying amount in the original
        # line to discriminate DEPOSITS vs WITHDRAWALS. ICICI prints them
        # in dedicated columns ~20 chars apart, so even with text-
        # extraction whitespace wobble the positional check is robust.
        first_amount_match = line.match(AMOUNT_RE)
        if first_amount_match
          pos = first_amount_match.begin(0)
          midpoint = (deposits_col + withdrawals_col) / 2
          column_direction = pos < midpoint ? 'credit' : 'debit'
        end
      end

      [amount, balance, column_direction]
    end

    def clean_description(rest)
      rest
        .gsub(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}/, ' ')   # inline dates
        .gsub(AMOUNT_RE, ' ')                              # money columns
        .sub(/\s{2,}\d{2,5}\s*\z/, ' ')                    # trailing Init.Br branch code
        .gsub(/\s+/, ' ')
        .strip[0..200]
    end

    def determine_tx_type(line:, rest:, amount:, balance:, running_balance:, column_direction: nil)
      # ICICI: when the column-position check has produced a direction,
      # trust it absolutely — it's read directly from which column
      # (DEPOSITS vs WITHDRAWALS) the amount sits in, which is the bank's
      # own ground truth.
      return column_direction if column_direction.present?

      if balance && running_balance && amount.positive?
        delta = balance - running_balance
        if delta.abs.between?(amount * 0.99 - 0.01, amount * 1.01 + 0.01)
          return delta.positive? ? 'credit' : 'debit'
        end
      end

      return 'credit' if line.match?(/\b(?:Cr|Credit)\b/i)
      return 'debit' if line.match?(/\b(?:Dr|Debit)\b/i)
      return 'credit' if StatementParsing::CreditKeywords.match?(rest[0..300])

      'debit'
    end

    def build_pdf_tx(tx)
      return nil if tx.blank? || tx[:amount].to_f < 0.01

      type = tx[:transaction_type]
      type = 'credit' if StatementParsing.credit?(tx[:description])

      {
        date: tx[:date],
        description: tx[:description],
        amount: tx[:amount].to_f.abs,
        transaction_type: type,
        source: 'regex',
      }
    end

    def parse_csv_amount_and_type(row:, debit_header:, credit_header:, amount_header:, type_header:, description: nil)
      if debit_header && credit_header
        debit_val = row[debit_header].to_s.gsub(/[^\d.]/, '').to_f
        credit_val = row[credit_header].to_s.gsub(/[^\d.]/, '').to_f
        return [debit_val, 'debit'] if debit_val.positive?
        return [credit_val, 'credit'] if credit_val.positive?
      end

      raw = amount_header ? row[amount_header].to_s : ''
      amount = raw.gsub(/[^\d.-]/, '').to_f

      if type_header && row[type_header].present?
        val = row[type_header].to_s.downcase
        type = (val.include?('cr') || val.include?('credit') || val.include?('income')) ? 'credit' : 'debit'
        return [amount.abs, type]
      end

      return [amount.abs, 'credit'] if StatementParsing.credit?(description)

      type = amount >= 0 ? 'debit' : 'credit'
      [amount.abs, type]
    end

    def find_column(headers, candidates)
      return nil if headers.blank?

      headers_lower = headers.map { |h| h.to_s.downcase.strip }
      candidates.each do |c|
        idx = headers_lower.index(c.downcase)
        return idx if idx
        partial = headers_lower.index { |h| h.include?(c.downcase) }
        return partial if partial
      end
      nil
    end

    def parse_date_flexible(str)
      TransactionValidator.parse_date(str) || Date.current
    end
  end
end
