# frozen_string_literal: true

require 'csv'

module InvestmentImports
  # Zerodha tradebook / tax P&L, Groww, HDFC Securities common CSV layouts.
  class BrokerCsvParser < BaseParser
    ZERODHA_HEADERS = /symbol|trade_date|quantity|price|trade_type/i
    GROWW_HEADERS = /stock_name|execution_date|type|quantity|price/i

    def parse
      rows = CSV.parse(@content.force_encoding('UTF-8'), headers: true, liberal_parsing: true)
      return [] if rows.empty?

      headers = rows.first.to_h.keys.map(&:to_s)
      if headers.join(' ').match?(ZERODHA_HEADERS)
        parse_zerodha(rows, headers)
      elsif headers.join(' ').match?(GROWW_HEADERS)
        parse_groww(rows, headers)
      else
        parse_generic(rows, headers)
      end.compact
    end

    private

    def parse_zerodha(rows, headers)
      date_col = find_col(headers, /trade_date|date|order_execution_time/i)
      sym_col = find_col(headers, /symbol|tradingsymbol/i)
      type_col = find_col(headers, /trade_type|type|transaction_type/i)
      qty_col = find_col(headers, /quantity|qty/i)
      amt_col = find_col(headers, /amount|value|net/i)

      rows.map do |r|
        type = r[type_col].to_s.downcase
        kind = type.include?('sell') ? 'sell' : 'buy'
        amt = r[amt_col].to_s.gsub(/[^\d.-]/, '').to_f
        amt = r[qty_col].to_f * r[find_col(headers, /price/i)].to_s.gsub(/[^\d.-]/, '').to_f if amt.zero?
        row(
          date: r[date_col],
          kind: kind,
          amount: amt,
          description: r[sym_col],
          asset_class: 'stock',
          symbol: r[sym_col],
          units: r[qty_col]
        )
      end
    end

    def parse_groww(rows, headers)
      date_col = find_col(headers, /execution|date/i)
      sym_col = find_col(headers, /stock|symbol|name/i)
      type_col = find_col(headers, /type|side/i)
      qty_col = find_col(headers, /quantity|qty/i)
      price_col = find_col(headers, /price|rate/i)

      rows.map do |r|
        kind = r[type_col].to_s.downcase.include?('sell') ? 'sell' : 'buy'
        qty = r[qty_col].to_f
        price = r[price_col].to_s.gsub(/[^\d.-]/, '').to_f
        row(
          date: r[date_col],
          kind: kind,
          amount: qty * price,
          description: r[sym_col],
          asset_class: 'stock',
          symbol: r[sym_col],
          units: qty
        )
      end
    end

    def parse_generic(rows, headers)
      date_col = find_col(headers, /date/i) || headers[0]
      desc_col = find_col(headers, /symbol|desc|name|particular/i) || headers[1]
      type_col = find_col(headers, /type|side|buy|sell/i)
      amt_col = find_col(headers, /amount|value|total/i) || headers[-1]

      rows.map do |r|
        kind = infer_kind(r[type_col])
        row(
          date: r[date_col],
          kind: kind,
          amount: r[amt_col].to_s.gsub(/[^\d.-]/, '').to_f,
          description: r[desc_col],
          asset_class: 'stock',
          symbol: r[desc_col]
        )
      end
    end

    def find_col(headers, pattern)
      headers.find { |h| h.match?(pattern) }
    end

    def infer_kind(val)
      s = val.to_s.downcase
      return 'sell' if s.include?('sell')
      return 'dividend' if s.include?('dividend')
      return 'interest' if s.include?('interest')

      'buy'
    end
  end
end
