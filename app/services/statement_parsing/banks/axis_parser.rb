# frozen_string_literal: true

module StatementParsing
  module Banks
    # Axis Bank savings/current statement parser.
    #
    # Layout: Axis prints the particulars line ABOVE its owning date row,
    # not after — opposite of HDFC/SBI/ICICI. The legacy RegexExtractor's
    # :axis branch buffers the preceding lines as a `pending_prefix` and
    # attaches them to the next date row. Without that buffering, every
    # transaction inherits the previous transaction's description (e.g.
    # SIP rows getting cross-contaminated with "Int.Pd:..." overflow text
    # — the bug that triggered this whole refactor in March).
    #
    # Axis also prints a 4-5 digit branch code in the rightmost column
    # ("Init.Br") that AMOUNT_RE used to misparse as a ₹195 / ₹256 amount.
    # The legacy parser handles that via a strict money regex.
    class AxisParser < BaseParser
      VERSION = '2026.05'
      EXTRACTION_METHOD = 'deterministic'

      def self.bank_name
        'Axis Bank'
      end
    end
  end
end
