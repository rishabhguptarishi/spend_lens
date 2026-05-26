# frozen_string_literal: true

require 'rails_helper'

# Phase-1 schema additions on investment_transactions:
#   external_id  — per-source dedup token (unique with user_id when set)
#   source_priority — auto-assigned from SourcePriority on save
#   confirmed_by — jsonb array, mutated via confirm_with!
#   superseded_by_id — self-referential FK
RSpec.describe InvestmentTransaction do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }
  let(:holding) { make_investment_holding(user: user, investment_account: account, name: 'INFY', asset_class: 'stock') }

  describe 'auto-assigned source_priority' do
    it 'sets source_priority from Investments::SourcePriority on create' do
      tx = user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'cdsl_cas',
        financial_year_start: FinancialYear.start_year_for(Date.today),
      )
      expect(tx.source_priority).to eq(100)
    end

    it 'respects an explicitly set source_priority (does not overwrite)' do
      tx = user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'manual', source_priority: 999,
        financial_year_start: FinancialYear.start_year_for(Date.today),
      )
      expect(tx.source_priority).to eq(999)
    end
  end

  describe 'external_id uniqueness' do
    it 'allows nil external_id on many rows (partial unique index)' do
      2.times do
        user.investment_transactions.create!(
          investment_account: account, investment_holding: holding,
          date: Date.today, kind: 'buy', amount: 1000.0,
          asset_class: 'stock', source: 'manual',
          financial_year_start: FinancialYear.start_year_for(Date.today),
        )
      end
      expect(user.investment_transactions.count).to eq(2)
    end

    it 'rejects two rows with the same external_id for the same user' do
      user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'bank_detect',
        financial_year_start: FinancialYear.start_year_for(Date.today),
        external_id: 'bank_txn:42',
      )

      expect {
        user.investment_transactions.create!(
          investment_account: account, investment_holding: holding,
          date: Date.today, kind: 'buy', amount: 1000.0,
          asset_class: 'stock', source: 'bank_detect',
          financial_year_start: FinancialYear.start_year_for(Date.today),
          external_id: 'bank_txn:42',
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same external_id across different users' do
      other = make_user
      other_account = make_investment_account(user: other)
      other_holding = make_investment_holding(user: other, investment_account: other_account)

      user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'bank_detect',
        financial_year_start: FinancialYear.start_year_for(Date.today),
        external_id: 'bank_txn:42',
      )
      expect {
        other.investment_transactions.create!(
          investment_account: other_account, investment_holding: other_holding,
          date: Date.today, kind: 'buy', amount: 1000.0,
          asset_class: 'stock', source: 'bank_detect',
          financial_year_start: FinancialYear.start_year_for(Date.today),
          external_id: 'bank_txn:42',
        )
      }.not_to raise_error
    end
  end

  describe '#confirm_with! and #superseded?' do
    let(:tx) do
      user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'cdsl_cas',
        financial_year_start: FinancialYear.start_year_for(Date.today),
      )
    end

    it 'appends a source name and returns truthy on first add' do
      result = tx.confirm_with!('broker_import')
      expect(result).to be_truthy
      expect(tx.reload.confirmed_by).to eq(['broker_import'])
    end

    it 'is idempotent: adding the same source twice is a no-op' do
      tx.confirm_with!('broker_import')
      expect { tx.confirm_with!('broker_import') }.not_to change { tx.reload.confirmed_by }
    end

    it 'ignores blank source names' do
      tx.confirm_with!('')
      expect(tx.reload.confirmed_by).to eq([])
    end

    it '#superseded? reflects superseded_by_id' do
      expect(tx).not_to be_superseded
      tx.update!(superseded_by_id: tx.id) # not realistic but safe for the predicate
      expect(tx.reload).to be_superseded
    end
  end

  describe 'scopes' do
    let!(:active_tx) do
      user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'cdsl_cas',
        financial_year_start: FinancialYear.start_year_for(Date.today),
      )
    end

    let!(:superseded_tx) do
      user.investment_transactions.create!(
        investment_account: account, investment_holding: holding,
        date: Date.today, kind: 'buy', amount: 1000.0,
        asset_class: 'stock', source: 'broker_import',
        financial_year_start: FinancialYear.start_year_for(Date.today),
        superseded_by_id: active_tx.id,
      )
    end

    it '.active excludes superseded rows' do
      expect(user.investment_transactions.active).to include(active_tx)
      expect(user.investment_transactions.active).not_to include(superseded_tx)
    end

    it '.superseded includes only superseded rows' do
      expect(user.investment_transactions.superseded).to include(superseded_tx)
      expect(user.investment_transactions.superseded).not_to include(active_tx)
    end
  end
end
