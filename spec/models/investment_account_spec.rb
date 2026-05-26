# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentAccount, type: :model do
  let(:user) { make_user }

  describe "validations" do
    it "requires a name" do
      acct = user.investment_accounts.new(account_kind: "broker")
      expect(acct).not_to be_valid
    end

    it "enforces account_kind inclusion in ACCOUNT_KINDS" do
      InvestmentAccount::ACCOUNT_KINDS.each do |kind|
        expect(user.investment_accounts.new(name: "X", account_kind: kind)).to be_valid
      end
      expect(user.investment_accounts.new(name: "X", account_kind: "bogus")).not_to be_valid
    end
  end

  describe "associations" do
    it "destroys holdings when account is destroyed" do
      assoc = described_class.reflect_on_association(:investment_holdings)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end

    it "nullifies investment_transactions when account is destroyed" do
      assoc = described_class.reflect_on_association(:investment_transactions)
      expect(assoc.options[:dependent]).to eq(:nullify)
    end
  end
end
