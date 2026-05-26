# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentHolding, type: :model do
  let(:user) { make_user }
  let(:account) { make_investment_account(user: user) }

  describe "validations" do
    it "requires name + asset_class" do
      expect(user.investment_holdings.new(investment_account: account)).not_to be_valid
    end

    it "validates asset_class is in the allowed list" do
      expect(user.investment_holdings.new(investment_account: account, name: "X", asset_class: "stock")).to be_valid
      expect(user.investment_holdings.new(investment_account: account, name: "X", asset_class: "bogus")).not_to be_valid
    end
  end
end
