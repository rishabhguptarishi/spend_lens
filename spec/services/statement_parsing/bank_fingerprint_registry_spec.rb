# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatementParsing::BankFingerprintRegistry do
  describe 'registered Tier-1 entries (loaded by config/initializers/bank_fingerprints.rb)' do
    it 'registers HDFC, ICICI, Axis, and SBI' do
      names = described_class.all.map(&:name)
      expect(names).to include('HDFC Bank', 'ICICI Bank', 'Axis Bank', 'State Bank of India')
    end

    it 'ICICI carries the multi-account + portfolio extraction features' do
      icici = described_class.lookup('ICICI Bank')
      expect(icici.features).to include(:multi_account_sections, :portfolio_extraction)
    end
  end

  describe '.detect' do
    it 'matches HDFC via IFSC prefix' do
      entry = described_class.detect("Transfer to HDFC0001234 account 12345")
      expect(entry&.name).to eq('HDFC Bank')
    end

    it 'matches ICICI via IFSC prefix' do
      entry = described_class.detect("IFSC: ICIC0006065")
      expect(entry&.name).to eq('ICICI Bank')
    end

    it 'matches Axis via IFSC prefix (UTIB0)' do
      entry = described_class.detect("A/C No: 920010 IFSC: UTIB0001234")
      expect(entry&.name).to eq('Axis Bank')
    end

    it 'matches SBI via IFSC prefix' do
      entry = described_class.detect("IFSC: SBIN0001234")
      expect(entry&.name).to eq('State Bank of India')
    end

    it 'matches via header patterns when no IFSC is present' do
      entry = described_class.detect("Welcome to www.hdfcbank.com\nMonthly statement")
      expect(entry&.name).to eq('HDFC Bank')
    end

    it 'prefers an ICICI header over HDFC beneficiary IFSCs in transaction rows' do
      text = <<~TEXT
        ICICI Bank Limited
        Statement of Account
        Account Number: 1234567890
        IFSC: ICIC0006065

        Date Narration Withdrawal Deposit Balance
        10/04/2026 NEFT TO HDFC0001234 BENEFICIARY 100.00 900.00
      TEXT

      expect(described_class.detect(text)&.name).to eq('ICICI Bank')
    end

    it 'prefers an HDFC header over SBI beneficiary IFSCs in transaction rows' do
      text = <<~TEXT
        HDFC BANK LIMITED
        Account Statement
        A/C No: 50100123456789
        IFSC: HDFC0001234

        Date Narration Withdrawal Deposit Balance
        12/04/2026 IMPS TO SBIN0011311 BENEFICIARY 500.00 5000.00
      TEXT

      expect(described_class.detect(text)&.name).to eq('HDFC Bank')
    end

    it 'returns nil when nothing matches (Tier-2 bank not yet fingerprinted)' do
      entry = described_class.detect("Welcome to Kotak Mahindra Bank account holder")
      expect(entry).to be_nil
    end

    it 'returns nil for blank text' do
      expect(described_class.detect('')).to be_nil
      expect(described_class.detect(nil)).to be_nil
    end

    it 'only scans the first 80 lines of text for header patterns' do
      noise = (["random filler line"] * 200).join("\n")
      text = "#{noise}\nwww.hdfcbank.com"
      # The header pattern lives beyond line 80 → no fingerprint match
      expect(described_class.detect(text)).to be_nil
    end
  end

  describe '.register' do
    it 'is idempotent: re-registering the same name replaces the previous entry' do
      original_count = described_class.all.size

      described_class.register('HDFC Bank',
        ifsc_prefix: 'HDFC0',
        header_patterns: [/HDFC/],
        parser: StatementParsing::Banks::HdfcParser,
        features: [],
      )

      expect(described_class.all.size).to eq(original_count)
    end
  end
end
