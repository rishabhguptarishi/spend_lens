# frozen_string_literal: true

module Investments
  # Builds a stable, source-specific dedup token for an
  # InvestmentTransaction. With the unique (user_id, external_id) index,
  # the same source re-uploading the same data cannot create duplicate
  # activity rows.
  #
  # See docs/INVESTMENT_ARCHITECTURE.html §5.3 for the template table.
  #
  # Returns nil when the source doesn't have a stable token (e.g.
  # 'manual'); in that case we fall back to the legacy 6-tuple dedup
  # in InvestmentLedgerImporter.
  module ExternalIdComputer
    extend self

    # Compute from a hash. Callers (writers) build the hash with whatever
    # source-specific identifiers they have at hand. Keys we look for:
    #
    #   :source           — required, drives the template choice
    #   :transaction_id   — bank Transaction#id for bank-detect activities
    #   :provider         — bank/broker/platform display name
    #   :folio            — passbook deposit_no / MF folio
    #   :isin / :symbol   — instrument identifier
    #   :date             — Date (or YYYY-MM-DD string)
    #   :units, :amount   — for activity-level dedup tuples
    #   :order_id / :trade_id / :document_id / :row_index — source-row id
    def call(source:, **rest)
      template = TEMPLATES[source.to_s]
      return nil unless template

      value = template.call(rest.with_defaults(source: source.to_s))
      sanitize(value)
    end

    private

    TEMPLATES = {
      'bank_detect' => ->(a) {
        a[:transaction_id].present? ? "bank_txn:#{a[:transaction_id]}" : nil
      },
      'bank_statement' => ->(a) {
        next nil if a[:folio].blank?

        provider = (a[:provider] || a[:bank_name]).to_s.downcase.tr(' ', '_')
        date = a[:date].present? ? a[:date].to_s : 'unknown'
        kind = a[:kind] || 'open'
        "passbook:#{provider}:#{a[:folio]}:#{date}:#{kind}"
      },
      'broker_import' => ->(a) {
        next "broker:#{a[:provider]}:order:#{a[:order_id]}" if a[:order_id].present? && a[:provider].present?
        next "broker:#{a[:provider]}:trade:#{a[:trade_id]}" if a[:trade_id].present? && a[:provider].present?
        next "tax_doc:#{a[:document_id]}:row:#{a[:row_index]}" if a[:document_id].present? && a[:row_index].present?
        next nil if a[:date].blank? || a[:amount].blank?

        # Fallback tuple — last-resort dedup for broker CSVs that don't
        # carry an order/trade id. Includes enough fields to be stable
        # for the SAME source re-uploading, while accepting that two
        # near-identical rows in one statement may not collapse.
        key_parts = [
          'broker',
          a[:provider],
          a[:date],
          a[:isin].presence || a[:symbol],
          format('%.2f', a[:amount].to_f),
          a[:units].present? ? format('%.4f', a[:units].to_f) : nil,
          a[:kind],
        ].compact
        key_parts.join(':')
      },
      'mf_cas' => ->(a) {
        next nil if a[:folio].blank? || a[:date].blank?

        amount = a[:amount].present? ? format('%.2f', a[:amount].to_f) : '0.00'
        units  = a[:units].present? ? format('%.4f', a[:units].to_f) : '0.0000'
        "mf_cas:#{a[:folio]}:#{a[:date]}:#{units}:#{amount}"
      },
      'cdsl_cas' => ->(a) {
        identifier = a[:isin].presence || a[:symbol].presence
        next nil if identifier.blank? || a[:date].blank?

        units = a[:units].present? ? format('%.4f', a[:units].to_f) : '0.0000'
        kind = a[:kind] || 'snapshot'
        "cdsl:#{identifier}:#{a[:date]}:#{units}:#{kind}"
      },
      'manual' => ->(_a) { nil },
    }.freeze

    def sanitize(value)
      return nil if value.blank?

      value.to_s.gsub(/\s+/, '_').strip
    end
  end
end
