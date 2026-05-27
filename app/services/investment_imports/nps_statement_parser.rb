# frozen_string_literal: true

require 'csv'

module InvestmentImports
  # NPS CRA / Protean transaction statement parser.
  #
  # Protean PDFs vary by year and CRA skin, but transaction rows consistently
  # expose PRAN, date, contribution/redemption labels, amount, and often units.
  class NpsStatementParser < BaseParser
    PRAN_RE = /\bPRAN\s*[:\-]?\s*(\d{12})\b/i
    TIER_RE = /\bTier\s*[- ]?(I{1,2}|1|2)\b/i
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
      pran = extract_pran(text)
      tier = extract_tier(text)
      date_col = find_col(headers, /date|transaction/i)
      desc_col = find_col(headers, /desc|particular|type|remarks/i)
      amount_col = find_col(headers, /amount|contribution|redemption|withdraw/i)
      units_col = find_col(headers, /units|unit/i)
      scheme_col = find_col(headers, /scheme|fund|pfm/i)

      rows.filter_map do |r|
        desc = r[desc_col].presence || r[scheme_col].presence || 'NPS statement'
        build_row(
          date: r[date_col],
          kind: infer_kind(desc),
          amount: money(r[amount_col]),
          description: desc,
          units: units_col ? money(r[units_col]) : nil,
          pran: pran,
          tier: tier
        )
      end
    end

    def parse_text(text)
      pran = extract_pran(text)
      tier = extract_tier(text)

      text.lines.filter_map do |line|
        next unless line.match?(DATE_TOKEN)

        date_token = line[DATE_TOKEN]
        remainder = line.sub(date_token, '').squish
        next unless remainder.match?(/contribution|deposit|redemption|withdraw|switch|unit|tier/i)

        values = remainder.scan(NUMBER).map { |v| money(v) }.select(&:positive?)
        next if values.empty?

        amount = pick_amount(values)
        units = pick_units(values, amount)
        build_row(
          date: date_token,
          kind: infer_kind(remainder),
          amount: amount,
          description: clean_description(remainder),
          units: units,
          pran: pran,
          tier: tier
        )
      end
    end

    def build_row(date:, kind:, amount:, description:, units:, pran:, tier:)
      label = ["NPS", tier.presence, description.to_s.presence].compact.join(' - ')
      r = row(
        date: parse_date_token(date),
        kind: kind,
        amount: amount,
        description: label,
        asset_class: 'nps',
        symbol: pran.presence || 'NPS',
        units: units,
      )
      return nil unless r

      r.merge(folio: pran, pran: pran, tier: tier, provider: 'Protean CRA')
    end

    def infer_kind(desc)
      s = desc.to_s.downcase
      return 'sell' if s.match?(/redemption|withdraw|exit/)
      return 'transfer_out' if s.match?(/switch\s*out/)
      return 'transfer_in' if s.match?(/switch\s*in/)

      'contribution'
    end

    def pick_amount(values)
      values.max
    end

    def pick_units(values, amount)
      candidates = values.reject { |v| v == amount }
      candidates.find { |v| v.positive? && v < 1_000_000 }
    end

    def clean_description(text)
      text.gsub(NUMBER, ' ').squish.presence || 'NPS transaction'
    end

    def extract_pran(text)
      text.to_s[PRAN_RE, 1]
    end

    def extract_tier(text)
      raw = text.to_s[TIER_RE, 1]
      return nil if raw.blank?

      raw.match?(/2|II/i) ? 'Tier II' : 'Tier I'
    end

    def csv_like?(text)
      first = text.lines.first.to_s
      first.include?(',') && first.match?(/date|pran|contribution|units|amount/i)
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
