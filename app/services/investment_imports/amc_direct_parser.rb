# frozen_string_literal: true

require 'csv'

module InvestmentImports
  # AMC direct folio statement parser for single-AMC PDFs/text exports.
  #
  # CAS remains the canonical multi-AMC source, but direct AMC statements are
  # common for HDFC/SBI/ICICI/etc. folios. This parser keeps folio + AMC context
  # so holdings dedupe via the existing MF folio identity rule.
  class AmcDirectParser < BaseParser
    FOLIO_RE = /\bFolio(?:\s+No\.?|\s+Number)?\s*[:\-]?\s*([A-Z0-9\/-]+)/i
    ISIN_RE = /\b(IN[A-Z0-9]{10})\b/
    NUMBER = /-?[\d,]+(?:\.\d+)?/
    DATE_TOKEN = %r{\d{1,2}[-/][A-Za-z]{3}[-/]\d{2,4}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|\d{4}-\d{1,2}-\d{1,2}}

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
      amc = infer_amc(text)
      date_col = find_col(headers, /date|transaction/i)
      desc_col = find_col(headers, /desc|particular|transaction|type/i)
      scheme_col = find_col(headers, /scheme|fund|plan/i)
      amount_col = find_col(headers, /amount|value/i)
      units_col = find_col(headers, /units|unit/i)
      folio_col = find_col(headers, /folio/i)
      isin_col = find_col(headers, /isin/i)

      rows.filter_map do |r|
        desc = r[desc_col].presence || r[scheme_col].presence || 'AMC direct'
        build_row(
          date: r[date_col],
          kind: map_kind(desc),
          amount: money(r[amount_col]),
          description: r[scheme_col].presence || desc,
          units: units_col ? money(r[units_col]) : nil,
          folio: r[folio_col].presence || extract_folio(text),
          isin: r[isin_col].presence || r.to_h.values.join(' ')[ISIN_RE, 1],
          amc: amc
        )
      end
    end

    def parse_text(text)
      folio = extract_folio(text)
      amc = infer_amc(text)
      current_scheme = nil
      current_isin = nil

      text.lines.filter_map do |line|
        stripped = line.squish
        next if stripped.blank?

        current_isin = stripped[ISIN_RE, 1] if stripped.match?(ISIN_RE)
        current_scheme = clean_scheme(stripped) if scheme_line?(stripped)
        next unless stripped.match?(DATE_TOKEN)

        date_token = stripped[DATE_TOKEN]
        remainder = stripped.sub(date_token, '').squish
        next unless remainder.match?(/purchase|redemption|switch|sip|systematic|dividend|idcw|reinvest/i)

        values = remainder.scan(NUMBER).map { |v| money(v) }.select(&:positive?)
        next if values.empty?

        amount = pick_amount(values)
        units = pick_units(values, amount)
        build_row(
          date: date_token,
          kind: map_kind(remainder),
          amount: amount,
          description: current_scheme || clean_description(remainder),
          units: units,
          folio: folio,
          isin: current_isin,
          amc: amc
        )
      end
    end

    def build_row(date:, kind:, amount:, description:, units:, folio:, isin:, amc:)
      r = row(
        date: parse_date_token(date),
        kind: kind,
        amount: amount,
        description: isin.present? ? "#{description} (#{isin})" : description,
        asset_class: 'mutual_fund',
        symbol: isin,
        units: units,
      )
      return nil unless r

      r.merge(folio: folio, isin: isin, amc: amc, provider: amc.presence || 'AMC Direct')
    end

    def map_kind(desc)
      s = desc.to_s.downcase
      return 'sell' if s.match?(/redemption|switch\s*out|withdraw/)
      return 'dividend' if s.match?(/dividend|idcw/)
      return 'sip' if s.match?(/sip|systematic/)

      'buy'
    end

    def extract_folio(text)
      text.to_s[FOLIO_RE, 1]
    end

    KNOWN_AMCS = [
      'HDFC Mutual Fund',
      'SBI Mutual Fund',
      'ICICI Prudential Mutual Fund',
      'Axis Mutual Fund',
      'Kotak Mutual Fund',
      'Nippon India Mutual Fund',
      'UTI Mutual Fund',
      'DSP Mutual Fund',
      'Tata Mutual Fund',
      'Mirae Asset Mutual Fund',
      'Franklin Templeton Mutual Fund',
      'Quant Mutual Fund',
      'Parag Parikh Mutual Fund',
      'Aditya Birla Sun Life Mutual Fund',
    ].freeze

    def infer_amc(text)
      KNOWN_AMCS.find { |name| text.match?(/#{Regexp.escape(name)}/i) }
    end

    def scheme_line?(line)
      line.length < 180 &&
        line.match?(/fund|scheme|direct|regular|growth|idcw/i) &&
        !line.match?(DATE_TOKEN) &&
        !line.match?(/folio|statement|transaction|opening|closing/i)
    end

    def clean_scheme(line)
      line.sub(/\bISIN\s*[:\-]?\s*IN[A-Z0-9]{10}\b/i, '').squish
    end

    def clean_description(text)
      text.gsub(NUMBER, ' ').squish.presence || 'AMC direct transaction'
    end

    def pick_amount(values)
      values.max
    end

    def pick_units(values, amount)
      values.reject { |v| v == amount }.find { |v| v.positive? && v < 1_000_000 }
    end

    def csv_like?(text)
      first = text.lines.first.to_s
      first.include?(',') && first.match?(/date|folio|scheme|amount|units/i)
    end

    def find_col(headers, pattern)
      headers.find { |h| h.match?(pattern) }
    end

    def parse_date_token(token)
      parse_date(token.to_s.tr('/', '-'))
    end

    def money(value)
      value.to_s.delete(',').gsub(/[^\d.\-]/, '').to_f
    end
  end
end
