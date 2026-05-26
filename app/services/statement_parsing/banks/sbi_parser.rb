# frozen_string_literal: true

module StatementParsing
  module Banks
    # State Bank of India statement parser.
    #
    # Layout: single-account, balance-arithmetic-based. SBI YONO/Net
    # Banking PDFs are similar in shape to HDFC's so they share the
    # :other code path in the legacy RegexExtractor.
    #
    # Known quirk SBI has that HDFC doesn't: the description field
    # frequently contains a 22-30 char NEFT/UPI reference that can be
    # misread as an account number. The fingerprint patterns below pick
    # up "State Bank of India" in the header and the SBIN0XXXXX IFSC.
    class SbiParser < BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      def self.bank_name
        'State Bank of India'
      end
    end
  end
end
