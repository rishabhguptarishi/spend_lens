# frozen_string_literal: true

# Phase 3, schema: tracks which bank parser handled each Statement and
# whether the parse was reliable.
#
#   parser_name     — registry key of the bank parser used (e.g. 'ICICI Bank'),
#                     or nil when no fingerprint matched and we fell through to
#                     the generic regex pipeline.
#   parser_version  — parser's VERSION constant at the time of parse, so we
#                     can spot drift after a bank changes their layout
#                     ('2026.05', '2026.03', ...).
#   parse_quality   — jsonb dictionary with balance verification result and
#                     per-section parse metadata:
#                       {
#                         "balance_verified": true,
#                         "opening_balance":  12345.67,
#                         "closing_balance":  23456.78,
#                         "balance_delta":    0.04,
#                         "transactions_total_credit": ...,
#                         "transactions_total_debit":  ...,
#                         "extraction_method": "deterministic",
#                         "confidence": 0.95
#                       }
#                     The UI uses this to show a "parsing was unreliable"
#                     banner. NULL when no parser ran (failed/pending statements).
class AddParserMetadataToStatements < ActiveRecord::Migration[8.0]
  def change
    add_column :statements, :parser_name, :string
    add_column :statements, :parser_version, :string
    add_column :statements, :parse_quality, :jsonb, default: {}
  end
end
