# frozen_string_literal: true

require 'csv'

module InvestmentImports
  class GenericCsvParser < BaseParser
    def initialize(content, source:, financial_year_start:, column_mapping: {})
      super(content, source: source, financial_year_start: financial_year_start)
      @mapping = column_mapping.stringify_keys
    end

    def parse
      rows = CSV.parse(@content.force_encoding('UTF-8'), headers: true, liberal_parsing: true)
      return [] if rows.empty?

      headers = rows.first.to_h.keys
      date_col = @mapping['date'] || headers.find { |h| h.to_s.downcase.include?('date') }
      desc_col = @mapping['description'] || headers.find { |h| h.to_s.downcase.match?(/desc|name|symbol/) }
      kind_col = @mapping['kind'] || headers.find { |h| h.to_s.downcase.match?(/type|kind/) }
      amt_col = @mapping['amount'] || headers.find { |h| h.to_s.downcase.match?(/amount|value/) }

      rows.filter_map do |r|
        kind = @mapping['default_kind'].presence || infer_kind(r[kind_col])
        row(
          date: r[date_col],
          kind: kind,
          amount: r[amt_col],
          description: r[desc_col],
          asset_class: @mapping['asset_class'].presence || 'other'
        )
      end
    end

    private

    def infer_kind(val)
      s = val.to_s.downcase
      return 'sell' if s.include?('sell')
      return 'buy' if s.include?('buy')
      return 'dividend' if s.include?('dividend')
      return 'interest' if s.include?('interest')
      return 'contribution' if s.include?('contrib')

      'other'
    end
  end
end
