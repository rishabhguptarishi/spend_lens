# frozen_string_literal: true

module StatementParsing
  module Banks
    # Fallback parser when no fingerprint matches the uploaded statement.
    #
    # Used for:
    #   - Tier-2/3 banks we haven't fingerprinted yet (one PR each per
    #     the §3.1 rollout: Kotak → IDFC First → Yes → Federal → BoB
    #     → IndusInd → PNB → Canara)
    #   - CSV uploads (where the legacy RegexExtractor#extract_csv path
    #     is already format-agnostic)
    #   - Statements where the fingerprint match is ambiguous
    #
    # Carries a 'generic' name so dashboards can tell "we parsed this
    # without a bank-specific parser" apart from "we couldn't parse it
    # at all". When parser_name is 'generic' and parse_quality says
    # balance_verified is false, the UI prompts the user to upload CSV
    # instead (the §4.6 CSV-first nudge).
    class GenericParser < BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      def self.bank_name
        'generic'
      end
    end
  end
end
