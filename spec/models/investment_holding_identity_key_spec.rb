# frozen_string_literal: true

require 'rails_helper'

# Phase 1 schema additions on investment_holdings:
#   identity_key — canonical cross-source instrument identifier
#                   (unique per user where set)
#   ASSET_CLASSES extended with reit/invit/p2p/fractional_re/rsu/espp/esop
RSpec.describe InvestmentHolding do
  let(:user) { make_user }
  let(:account) do
    make_investment_account(user: user, name: 'ICICI Bank — PPF', provider: 'ICICI Bank', account_kind: 'ppf')
  end

  describe 'extended ASSET_CLASSES' do
    %w[reit invit p2p fractional_re rsu espp esop].each do |ac|
      it "accepts #{ac.inspect} as a valid asset_class" do
        holding = user.investment_holdings.new(
          investment_account: account, name: "Test #{ac}", asset_class: ac
        )
        expect(holding).to be_valid
      end
    end

    it 'still rejects truly unknown asset_classes' do
      holding = user.investment_holdings.new(
        investment_account: account, name: 'Bogus', asset_class: 'not_a_real_class'
      )
      expect(holding).not_to be_valid
      expect(holding.errors[:asset_class]).to be_present
    end
  end

  describe 'auto-assigned identity_key (before_validation on :create)' do
    it 'computes identity_key from holding attributes on create' do
      h = user.investment_holdings.create!(
        investment_account: account,
        asset_class: 'ppf',
        name: 'ICICI PPF 000418336506',
        folio: '000418336506',
        metadata: { bank_name: 'ICICI Bank', account_no: '000418336506' },
      )
      expect(h.identity_key).to eq('PPF:ICICI Bank:000418336506')
    end

    it 'respects an explicitly provided identity_key (no overwrite)' do
      h = user.investment_holdings.create!(
        investment_account: account,
        asset_class: 'stock',
        name: 'Reliance',
        symbol: 'INE002A01018',
        identity_key: 'OVERRIDE_KEY',
      )
      expect(h.identity_key).to eq('OVERRIDE_KEY')
    end

    it 'does NOT recompute identity_key on subsequent updates' do
      h = user.investment_holdings.create!(
        investment_account: account,
        asset_class: 'stock',
        name: 'Reliance',
        symbol: 'INE002A01018',
      )
      key = h.identity_key
      h.update!(name: 'Renamed') # would change name-fallback if recomputed
      expect(h.reload.identity_key).to eq(key)
    end

    it 'leaves identity_key nil when the holding lacks enough metadata' do
      h = user.investment_holdings.create!(
        investment_account: account,
        asset_class: 'real_estate',
        name: 'Bangalore Flat',
      )
      expect(h.identity_key).to be_nil
    end
  end

  describe 'unique index on (user_id, identity_key)' do
    it 'rejects two holdings with the same identity_key for one user' do
      user.investment_holdings.create!(
        investment_account: account, asset_class: 'stock', name: 'A',
        symbol: 'INE002A01018', identity_key: 'INE002A01018',
      )

      expect {
        user.investment_holdings.create!(
          investment_account: account, asset_class: 'stock', name: 'B',
          symbol: 'INE002A01018', identity_key: 'INE002A01018',
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same identity_key across different users' do
      other = make_user
      other_account = make_investment_account(user: other)

      user.investment_holdings.create!(
        investment_account: account, asset_class: 'stock', name: 'A',
        identity_key: 'INE002A01018',
      )
      expect {
        other.investment_holdings.create!(
          investment_account: other_account, asset_class: 'stock', name: 'A',
          identity_key: 'INE002A01018',
        )
      }.not_to raise_error
    end

    it 'allows many holdings with nil identity_key (partial unique index)' do
      2.times do
        user.investment_holdings.create!(
          investment_account: account, asset_class: 'real_estate', name: 'Flat',
        )
      end
      expect(user.investment_holdings.count).to eq(2)
    end
  end
end
