# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatementParsing::BalanceVerifier do
  let(:txns) do
    [
      { date: Date.new(2026, 4, 5),  description: 'UPI/AMAZON',     amount: 500.0,   transaction_type: 'debit' },
      { date: Date.new(2026, 4, 10), description: 'NEFT/SALARY',    amount: 50_000.0, transaction_type: 'credit' },
      { date: Date.new(2026, 4, 15), description: 'ATM',            amount: 2_000.0,  transaction_type: 'debit' },
    ]
  end

  describe '.verify' do
    it 'returns verified: true when opening + Σcredits − Σdebits ≈ closing' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 72_500.0,
      )
      expect(result.verified).to be true
      expect(result.delta).to be_within(0.01).of(0.0)
    end

    it 'tolerates a sub-tolerance rounding delta' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 72_500.30, # 30 paise off → within tolerance
      )
      expect(result.verified).to be true
      expect(result.delta.abs).to be <= 0.5
    end

    it 'returns verified: false when the arithmetic doesn\'t balance (parser drift)' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 50_000.0, # off by ~22.5k → parser missed rows
      )
      expect(result.verified).to be false
      expect(result.delta.abs).to be > 0.5
    end

    it 'returns verified: nil when opening balance is missing (can\'t check)' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: nil,
        closing_balance: 72_500.0,
      )
      expect(result.verified).to be_nil
      expect(result).not_to be_verifiable
    end

    it 'returns verified: nil when closing balance is missing' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: nil,
      )
      expect(result.verified).to be_nil
    end

    it 'accepts a custom tolerance' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 72_503.0, # 3 rupees off
        tolerance: 5.0,
      )
      expect(result.verified).to be true
    end

    it 'records total_credit and total_debit for downstream telemetry' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 72_500.0,
      )
      expect(result.total_credit).to eq(50_000.0)
      expect(result.total_debit).to eq(2_500.0)
    end

    it 'handles string-keyed transaction hashes (legacy persister format)' do
      string_keyed = txns.map(&:stringify_keys)
      result = described_class.verify(
        transactions: string_keyed,
        opening_balance: 25_000.0,
        closing_balance: 72_500.0,
      )
      expect(result.verified).to be true
    end

    it 'works with an empty transactions list (still verifiable if opening==closing)' do
      result = described_class.verify(
        transactions: [],
        opening_balance: 1_000.0,
        closing_balance: 1_000.0,
      )
      expect(result.verified).to be true
    end

    it '#to_h flattens into a parse_quality-compatible jsonb dictionary' do
      result = described_class.verify(
        transactions: txns,
        opening_balance: 25_000.0,
        closing_balance: 72_500.0,
      )
      h = result.to_h
      expect(h).to include(
        balance_verified: true,
        opening_balance: 25_000.0,
        closing_balance: 72_500.0,
        transactions_total_credit: 50_000.0,
        transactions_total_debit: 2_500.0,
      )
    end
  end
end
