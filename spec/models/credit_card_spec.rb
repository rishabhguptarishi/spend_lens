# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditCard, type: :model do
  let(:user) { make_user }

  it "requires a name" do
    expect(user.credit_cards.new).not_to be_valid
    expect(user.credit_cards.new(name: "HDFC Regalia")).to be_valid
  end

  describe "reward-structure accessors" do
    let(:card) do
      user.credit_cards.create!(
        name: "HDFC Regalia",
        rewards_structure: {
          "category_rewards" => [{ "category" => "Dining", "rate" => 4 }],
          "special_offers" => ["10% off on movies"],
          "base_reward" => { "rate" => 1, "description" => "1 pt per ₹100" },
        }
      )
    end

    it "exposes category_rewards as an array" do
      expect(card.category_rewards).to be_an(Array)
      expect(card.category_rewards.first["category"]).to eq("Dining")
    end

    it "exposes special_offers as an array" do
      expect(card.special_offers).to include("10% off on movies")
    end

    it "exposes base_reward as a hash" do
      expect(card.base_reward["rate"]).to eq(1)
    end

    it "returns safe empty defaults when rewards_structure is nil" do
      bare = user.credit_cards.create!(name: "Bare", rewards_structure: nil)
      expect(bare.category_rewards).to eq([])
      expect(bare.special_offers).to eq([])
      expect(bare.base_reward).to eq({})
    end
  end
end
