# frozen_string_literal: true

require 'csv'

module InvestmentImports
  # EPFO member passbook parser.
  #
  # Supports CSV exports and text extracted from EPFO passbook PDFs. The parser
  # emits one ledger row per contribution/interest/withdrawal component so EPF
  # totals remain auditable even when the PDF prints employee, employer, and
  # pension columns separately.
  class EpfPassbookParser < BaseParser
    UAN_RE = /\bUAN\s*[:\-]?\s*(\d{12})\b/i
    NUMBER = /-?[\d,]+(?:\.\d+)?/
    DATE_TOKEN = %r{\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|\d{4}-\d{1,2}-\d{1,2}}

    def parse
      text = @content.to_s
      return parse_csv(text) if csv_like?(text)

      parse_text(text)
    end

    private

    def parse_csv(text)
      rows = CSV.parse(text.force_encoding('UTF-8'), headers: true, liberal_parsing: true)
      return [] if rows.empty?

      headers = rows.first.to_h.keys.map(&:to_s)
      uan = extract_uan(text)
      date_col = find_col(headers, /date|wage\s*month|month/i)
      desc_col = find_col(headers, /desc|particular|remarks|type/i)
      employee_col = find_col(headers, /employee|ee\s*share|member/i)
      employer_col = find_col(headers, /employer|er\s*share/i)
      pension_col = find_col(headers, /pension|eps/i)
      interest_col = find_col(headers, /interest/i)
      withdrawal_col = find_col(headers, /withdraw|claim|advance/i)
      amount_col = find_col(headers, /\bamount\b|credit|deposit/i)

      rows.flat_map do |r|
        date = parse_statement_date(r[date_col])
        desc = r[desc_col].presence || 'EPF passbook'
        components = []
        components << component_row(date, 'contribution', r[employee_col], "#{desc} - employee share", uan) if employee_col
        components << component_row(date, 'contribution', r[employer_col], "#{desc} - employer share", uan) if employer_col
        components << component_row(date, 'contribution', r[pension_col], "#{desc} - pension share", uan) if pension_col
        components << component_row(date, 'interest', r[interest_col], "#{desc} - interest", uan) if interest_col
        components << component_row(date, 'maturity', r[withdrawal_col], "#{desc} - withdrawal", uan) if withdrawal_col
        components << component_row(date, infer_kind(desc), r[amount_col], desc, uan) if components.empty? && amount_col
        components.compact
      end
    end

    def parse_text(text)
      uan = extract_uan(text)
      text.lines.flat_map do |line|
        parse_passbook_line(line, uan)
      end.compact
    end

    def parse_passbook_line(line, uan)
      return [] unless line.match?(DATE_TOKEN)

      date_token = line[DATE_TOKEN]
      date = parse_statement_date(date_token)
      return [] unless date

      desc = line.sub(date_token, '').squish
      values = numeric_values(desc)
      return [] if values.empty?

      if desc.match?(/interest/i)
        [component_row(date, 'interest', values.first, "EPF interest #{date}", uan)]
      elsif desc.match?(/withdraw|claim|advance|settlement/i)
        [component_row(date, 'maturity', values.first, "EPF withdrawal #{date}", uan)]
      elsif values.size >= 3
        [
          component_row(date, 'contribution', values[0], "EPF employee contribution #{date}", uan),
          component_row(date, 'contribution', values[1], "EPF employer contribution #{date}", uan),
          component_row(date, 'contribution', values[2], "EPF pension contribution #{date}", uan),
        ]
      else
        [component_row(date, 'contribution', values.first, "EPF contribution #{date}", uan)]
      end
    end

    def component_row(date, kind, amount, description, uan)
      r = row(
        date: date,
        kind: kind,
        amount: money(amount),
        description: description,
        asset_class: 'epf',
        symbol: uan.presence || 'EPF',
      )
      return nil unless r

      r.merge(folio: uan, uan: uan, provider: 'EPFO')
    end

    def infer_kind(desc)
      s = desc.to_s.downcase
      return 'interest' if s.include?('interest')
      return 'maturity' if s.match?(/withdraw|claim|advance|settlement/)

      'contribution'
    end

    def extract_uan(text)
      text.to_s[UAN_RE, 1]
    end

    def csv_like?(text)
      first = text.lines.first.to_s
      first.include?(',') && first.match?(/date|uan|employee|employer|amount/i)
    end

    def find_col(headers, pattern)
      headers.find { |h| h.match?(pattern) }
    end

    def parse_statement_date(value)
      return nil if value.blank?

      s = value.to_s.strip
      return Date.new(Regexp.last_match(2).to_i, Regexp.last_match(1).to_i, 1) if s.match?(/\A(\d{1,2})[-\/](\d{4})\z/)

      parse_date(s)
    end

    def money(value)
      value.to_s.delete(',').gsub(/[^\d.\-]/, '').to_f
    end

    def numeric_values(text)
      text.scan(NUMBER)
          .reject { |token| token.match?(/\A(?:19|20)\d{2}\z/) }
          .map { |v| money(v) }
          .select(&:positive?)
    end
  end
end
