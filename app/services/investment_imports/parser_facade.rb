# frozen_string_literal: true

module InvestmentImports
  class ParserFacade
    def self.call(file_content:, filename:, source:, financial_year_start:, column_mapping: {})
      ext = File.extname(filename.to_s).downcase.delete('.')
      text = if ext == 'pdf'
               StatementParsing::TextExtractor.extract(file_content, extension: 'pdf')
             else
               file_content.force_encoding('UTF-8')
             end

      rows = case source.to_s
             when 'zerodha', 'groww', 'hdfc_sec'
               BrokerCsvParser.parse(text, source: source, financial_year_start: financial_year_start)
             when 'mf_cas'
               MfCasParser.parse(text, source: source, financial_year_start: financial_year_start)
             when 'cdsl_cas'
               # Deterministic regex pass extracts amounts/dates/units/ISINs.
               # An optional AI pass then rewrites only the human-readable
               # `:description` field — numbers stay verbatim, ISINs are
               # anchored. Falls back silently if AI is unavailable.
               parsed = CdslCasParser.parse(text, source: source, financial_year_start: financial_year_start)
               SecurityNameEnricher.call(parsed)
             when 'generic_csv'
               GenericCsvParser.new(text, source: source, financial_year_start: financial_year_start, column_mapping: column_mapping).parse
             else
               BrokerCsvParser.parse(text, source: source, financial_year_start: financial_year_start)
             end

      rows.map { |r| r.merge(date: r[:date].to_s, selected: true) }
    end
  end
end
