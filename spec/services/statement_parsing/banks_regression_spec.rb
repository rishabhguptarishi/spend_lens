# frozen_string_literal: true

require 'rails_helper'

# Per-bank regression suite (§4.3 of the architecture doc).
#
# Each bank fingerprinted by BankFingerprintRegistry MUST have:
#   1. a sanitised text fixture at spec/fixtures/statements/<slug>_sample.txt
#   2. an expected YAML at  spec/fixtures/statements/<slug>_expected.yml
#
# The runner below iterates every fixture pair, fingerprints the text,
# runs the per-bank parser, and asserts:
#   - the fingerprint matched the expected bank
#   - the parser stamped the expected VERSION
#   - the right NUMBER of transactions came out
#   - SAMPLE transactions match on date / amount / direction / description
#     (only fields the expected YAML names; everything else is allowed
#     to drift so individual descriptions can vary)
#
# When a bank changes layout and this spec fails:
#   1. Drop their new sanitised PDF text into the fixture
#   2. Update expected YAML
#   3. Bump VERSION on the parser
RSpec.describe 'Per-bank parser regression suite' do
  fixture_dir = Rails.root.join('spec/fixtures/statements')

  FIXTURES = [
    { slug: 'hdfc_savings',           bank: 'HDFC Bank' },
    { slug: 'icici_consolidated',     bank: 'ICICI Bank' },
    { slug: 'axis_savings',           bank: 'Axis Bank' },
    { slug: 'sbi_savings',            bank: 'State Bank of India' },
  ].freeze

  FIXTURES.each do |fixture|
    describe "#{fixture[:bank]} (#{fixture[:slug]})" do
      let(:text) { File.read(fixture_dir.join("#{fixture[:slug]}_sample.txt")) }
      let(:expected) { YAML.safe_load_file(fixture_dir.join("#{fixture[:slug]}_expected.yml")) }

      it 'fingerprint resolves to the right bank' do
        entry = StatementParsing::BankFingerprintRegistry.detect(text)
        expect(entry).to be_present
        expect(entry.name).to eq(fixture[:bank])
      end

      it 'parser stamps the expected name and version' do
        entry = StatementParsing::BankFingerprintRegistry.detect(text)
        result = entry.parser.new(content: text, format: :pdf).call
        expect(result.parser_name).to eq(expected['parser_name'])
        expect(result.parser_version).to eq(expected['parser_version'])
      end

      it 'emits the expected number of spendable transactions' do
        entry = StatementParsing::BankFingerprintRegistry.detect(text)
        result = entry.parser.new(content: text, format: :pdf).call
        expect(result.transactions.size).to eq(expected['transaction_count']),
          "Expected #{expected['transaction_count']} txns, got #{result.transactions.size}:\n" \
          "#{result.transactions.map { |t| "  - #{t[:date]} #{t[:transaction_type]} ₹#{t[:amount]} #{t[:description]}" }.join("\n")}"
      end

      it 'sample transactions match on date / amount / direction (and description if asserted)' do
        entry = StatementParsing::BankFingerprintRegistry.detect(text)
        result = entry.parser.new(content: text, format: :pdf).call

        Array(expected['sample_transactions']).each do |expected_tx|
          match = result.transactions.find do |t|
            t[:date].to_s == expected_tx['date'] &&
              t[:amount].to_f == expected_tx['amount'].to_f &&
              t[:transaction_type].to_s == expected_tx['transaction_type']
          end

          expect(match).to be_present,
            "No transaction matched #{expected_tx.inspect}\n" \
            "Got: #{result.transactions.map { |t| "  - #{t[:date]} #{t[:transaction_type]} ₹#{t[:amount]} #{t[:description]}" }.join("\n")}"

          if expected_tx['description_contains'].present?
            expect(match[:description].to_s.upcase)
              .to include(expected_tx['description_contains'].to_s.upcase)
          end
        end
      end

      if (expected_yml = YAML.safe_load_file(fixture_dir.join("#{fixture[:slug]}_expected.yml"))) && expected_yml['balance_verified']
        it 'balances under BalanceVerifier (opening + Σcredits − Σdebits ≈ closing)' do
          entry = StatementParsing::BankFingerprintRegistry.detect(text)
          result = entry.parser.new(content: text, format: :pdf).call
          balance = StatementParsing::BalanceVerifier.verify(
            transactions: result.transactions,
            opening_balance: result.opening_balance,
            closing_balance: result.closing_balance,
          )
          expect(balance.opening).to eq(expected_yml['opening_balance']) if expected_yml['opening_balance']
          expect(balance.closing).to eq(expected_yml['closing_balance']) if expected_yml['closing_balance']
          expect(balance.verified).to be(true),
            "balance.delta=#{balance.delta} tolerance=#{balance.tolerance}"
        end
      end
    end
  end
end
