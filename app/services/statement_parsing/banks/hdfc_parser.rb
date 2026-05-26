# frozen_string_literal: true

module StatementParsing
  module Banks
    # HDFC Bank savings/current statement parser.
    #
    # Layout: single-account, balance-arithmetic-based (date | description |
    # withdrawal | deposit | balance). The legacy RegexExtractor's :other
    # branch already handles it correctly, so this class delegates the
    # actual extraction and just stamps version/fingerprint metadata.
    #
    # When HDFC ships a new layout, this is the file that bumps VERSION and
    # gains a bank-specific parse_pdf override.
    class HdfcParser < BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      def self.bank_name
        'HDFC Bank'
      end
    end
  end
end
