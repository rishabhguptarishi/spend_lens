# frozen_string_literal: true

module StatementParsing
  # Shared keyword regex used across the parsing pipeline to detect
  # credit-type transactions whose sign isn't obvious from the amount column
  # (e.g. salary credits on a credit-card statement). Kept here as a proper
  # Zeitwerk-friendly module so the constant is autoloaded reliably.
  module CreditKeywords
    # Notes on the additions:
    #   * `Int\.Pd` is how Axis abbreviates "Interest Paid" inside the
    #     description (e.g. "SB:917010081786930:Int.Pd:01-04-2025 to 30-").
    #     The bare \bINTEREST\b token does not match "Int.Pd" because the
    #     period terminates the word.
    #   * `ACH-CR` / `ACH CR` covers dividend / mutual-fund payouts that
    #     come through NACH (e.g. "ACH-CR-VEDANTA LIMITED-NACH-").
    #   * `IMPS\s+CR` / `UPI\s+CR` mirror the existing NEFT/RTGS credits.
    REGEX = /\b(SALARY|CRV|CREDIT|REFUND|REVERSAL|INTEREST|DEPOSIT|A\s*AINT|NEFT\s+CR|RTGS\s+CR|IMPS\s+CR|UPI\s+CR|ACH[- ]CR|Int\.Pd)\b/i

    def self.match?(description)
      description.to_s.match?(REGEX)
    end
  end
end
