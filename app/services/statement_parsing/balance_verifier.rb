# frozen_string_literal: true

module StatementParsing
  # Phase 3, §4.5: the "golden rule" parser sanity check.
  #
  #   opening_balance + Σcredits − Σdebits  ≈  closing_balance ± ₹0.50
  #
  # If this doesn't hold, the parser dropped (or invented) transactions
  # and the user should see a "parsing was unreliable" banner — never
  # silently swallow a quarter-million-rupee parse miss again.
  #
  # The tolerance is loose (50 paise) on purpose: a small rounding delta
  # is normal because some banks round per-row interest credits to the
  # nearest paise while computing the closing balance from unrounded
  # intermediates. The threshold catches genuine drift (hundreds or
  # thousands of rupees off) without flagging legitimate rounding.
  #
  # Both balances are optional. If either is unknown (bank header doesn't
  # print one, scanned PDF garbled the digits, ...), #verify returns a
  # Result with verified: nil — meaning "couldn't check", which the UI
  # surfaces differently from "checked and failed".
  module BalanceVerifier
    extend self

    DEFAULT_TOLERANCE = 0.5 # rupees

    Result = Struct.new(:verified, :delta, :tolerance, :opening, :closing, :total_credit, :total_debit, keyword_init: true) do
      def verifiable?
        !verified.nil?
      end

      def to_h
        {
          balance_verified: verified,
          balance_delta: delta,
          balance_tolerance: tolerance,
          opening_balance: opening,
          closing_balance: closing,
          transactions_total_credit: total_credit,
          transactions_total_debit: total_debit,
        }
      end
    end

    def verify(transactions:, opening_balance:, closing_balance:, tolerance: DEFAULT_TOLERANCE)
      txs = Array(transactions)
      credit = sum_for(txs, 'credit')
      debit  = sum_for(txs, 'debit')

      if opening_balance.nil? || closing_balance.nil?
        return Result.new(
          verified: nil,
          delta: nil,
          tolerance: tolerance,
          opening: opening_balance,
          closing: closing_balance,
          total_credit: credit,
          total_debit: debit,
        )
      end

      expected = opening_balance.to_f + credit - debit
      delta = (expected - closing_balance.to_f).round(2)

      Result.new(
        verified: delta.abs <= tolerance,
        delta: delta,
        tolerance: tolerance,
        opening: opening_balance.to_f,
        closing: closing_balance.to_f,
        total_credit: credit,
        total_debit: debit,
      )
    end

    private

    def sum_for(transactions, type)
      transactions.select { |t| t[:transaction_type].to_s == type || t['transaction_type'].to_s == type }
        .sum { |t| (t[:amount] || t['amount']).to_f.abs }
    end
  end
end
