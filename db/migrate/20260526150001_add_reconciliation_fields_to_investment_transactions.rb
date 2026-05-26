# frozen_string_literal: true

# Phase 1, Migrations A + C: per-source dedup key + cross-source priority
# + supersession chain on investment_transactions.
#
#   external_id     — stable, source-specific dedup token (e.g.
#                     "bank_txn:42", "passbook:icici:1539:2026-02-07",
#                     "mf_cas:11223344:2026-04-05:25.43:8023.45").
#                     Same source re-uploading same data CANNOT duplicate.
#                     (DB-level unique constraint on (user_id, external_id)
#                     where external_id is present.)
#
#   source_priority — integer rank (40 manual … 100 cdsl_cas) so the
#                     ActivityReconciler can decide which competing
#                     view of "same event" is canonical.
#
#   confirmed_by    — jsonb array of source names that independently
#                     attest to this activity. Drives the UI's
#                     "✓ matched across 2 sources" badge.
#
#   superseded_by_id — when a lower-priority activity is matched by a
#                      higher-priority activity for the same event, the
#                      lower one keeps existing (audit log) but points
#                      to the canonical one and is hidden from totals.
class AddReconciliationFieldsToInvestmentTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :investment_transactions, :external_id, :string
    add_column :investment_transactions, :source_priority, :integer
    add_column :investment_transactions, :confirmed_by, :jsonb, default: []
    add_column :investment_transactions, :superseded_by_id, :bigint

    add_index :investment_transactions, %i[user_id external_id],
      unique: true,
      where: 'external_id IS NOT NULL',
      name: 'index_investment_transactions_on_user_external_id'

    add_index :investment_transactions, :superseded_by_id,
      name: 'index_investment_transactions_on_superseded_by_id'

    add_foreign_key :investment_transactions, :investment_transactions,
      column: :superseded_by_id, on_delete: :nullify
  end
end
