# frozen_string_literal: true

module StatementParsing
  module Banks
    # ICICI Bank statement parser.
    #
    # Layout: consolidated multi-account statements that bundle savings,
    # PPF, FD/RD passbooks, and (sometimes) a credit card view in one PDF.
    # The §3 architecture doc tags this with two features:
    #
    #   :multi_account_sections — RegexExtractor segments the PDF on
    #                              "Statement of Transactions in Savings/
    #                              Current/Account/..." headers and only
    #                              emits transactions from spendable
    #                              sections.
    #   :portfolio_extraction  — PortfolioExtractor (run separately by
    #                            StatementParserService) walks PPF/FD/RD
    #                            blocks and creates InvestmentHoldings.
    #
    # The legacy RegexExtractor's :icici branch already does the
    # transaction extraction; this class will own bank-specific overrides
    # the day ICICI ships a layout change. For now it stamps fingerprint
    # metadata and exposes the feature flags.
    class IciciParser < BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      FEATURES = %i[multi_account_sections portfolio_extraction].freeze

      def self.bank_name
        'ICICI Bank'
      end

      def self.features
        FEATURES
      end
    end
  end
end
