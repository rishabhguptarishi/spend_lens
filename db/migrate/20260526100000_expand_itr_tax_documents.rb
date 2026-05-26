# frozen_string_literal: true

# Phase 3 of the ITR roadmap — expand itr_tax_documents to support the
# 30+ document types described in ItrDocumentRegistry.
#
# Two big shape changes:
#
# 1. Drop the (user_id, financial_year_start, document_type) UNIQUE index.
#    Reality is messier than the original schema assumed:
#      * a user can have multiple Form 16As (one per bank that deducted TDS)
#      * multiple LIC premium receipts, multiple donation receipts
#      * multiple broker P&Ls when they trade with multiple brokers
#      * multiple property sale deeds in the same FY
#    We replace it with a NON-unique composite index for lookup speed,
#    and enforce singleton-ness in the model (only types flagged
#    multiple_per_fy: false get the app-level uniqueness check).
#
# 2. Add columns that the registry needs to disambiguate multi-instance
#    docs and store free-form metadata:
#      * payer_name      — "HDFC Bank" / "Acme Pvt Ltd" / "LIC Policy 123"
#      * source_label    — user-supplied label shown in UI (eg "Q2 rent")
#      * period_start    — for documents that span a sub-period of FY
#      * period_end      — (eg salary slip = 1 month, FD interest cert = full FY)
#      * deduction_section — denormalised section ('80C', '80D', ...) for
#                          fast aggregation in TaxSavingsAdvisorService
#                          without re-reading the registry per row
class ExpandItrTaxDocuments < ActiveRecord::Migration[8.0]
  def change
    remove_index :itr_tax_documents,
                 name: 'index_itr_docs_on_user_fy_type',
                 if_exists: true

    change_table :itr_tax_documents, bulk: true do |t|
      t.string :payer_name
      t.string :source_label
      t.date   :period_start
      t.date   :period_end
      t.string :deduction_section
    end

    add_index :itr_tax_documents,
              [:user_id, :financial_year_start, :document_type],
              name: 'index_itr_docs_on_user_fy_type'

    add_index :itr_tax_documents,
              [:user_id, :financial_year_start, :deduction_section],
              name: 'index_itr_docs_on_user_fy_section'
  end
end
