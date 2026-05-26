# frozen_string_literal: true

module InvestmentImports
  class BaseParser
    def self.parse(content, source:, financial_year_start:)
      new(content, source: source, financial_year_start: financial_year_start).parse
    end

    def initialize(content, source:, financial_year_start:)
      @content = content
      @source = source
      @fy = financial_year_start.to_i
    end

    def parse
      raise NotImplementedError
    end

    private

    def row(date:, kind:, amount:, description:, asset_class: 'stock', symbol: nil, units: nil)
      d = parse_date(date)
      return nil unless d && amount.to_f.positive?

      fy = FinancialYear.start_year_for(d)
      {
        date: d,
        kind: kind,
        amount: amount.to_f.abs,
        description: description.to_s.strip.presence || 'Import',
        asset_class: asset_class,
        symbol: symbol,
        units: units,
        financial_year_start: fy,
        source: "broker_import",
      }
    end

    def parse_date(val)
      return val if val.is_a?(Date)
      return nil if val.blank?

      Date.parse(val.to_s)
    rescue ArgumentError
      nil
    end
  end
end
