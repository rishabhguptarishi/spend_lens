# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ai::Tools propose-* (write-action) tools", type: :service do
  let(:user) { make_user }
  let(:food_cat) { user.categories.find_by(name: "Food & Dining") }

  describe Ai::Tools::ProposeCreateCategory do
    it "mints a signed proposal token for a new category" do
      result = described_class.new(user).call({ "name" => "Subscriptions", "color" => "#abcdef" })
      proposal = result[:proposal]
      expect(proposal).to include(:token, :name, :color)
      expect(proposal[:kind]).to eq("create_category")

      payload = Ai::ProposalVerifier.verify(proposal[:token], user: user)
      expect(payload[:kind]).to eq("create_category")
      expect(payload[:args][:name]).to eq("Subscriptions")
    end

    it "rejects names that duplicate an existing category (case-insensitive)" do
      expect {
        described_class.new(user).call({ "name" => "FOOD & DINING" })
      }.to raise_error(Ai::Tools::Base::ToolError, /already exists/i)
    end

    it "silently drops an invalid color (does not reject the proposal)" do
      result = described_class.new(user).call({ "name" => "Foo", "color" => "not-a-hex" })
      expect(result[:proposal][:color]).to be_nil
    end

    it "rejects blank names" do
      expect {
        described_class.new(user).call({ "name" => "  " })
      }.to raise_error(Ai::Tools::Base::ToolError)
    end
  end

  describe Ai::Tools::ProposeCreateBudget do
    it "mints a proposal when a valid category is provided by id" do
      result = described_class.new(user).call({
        "category_id" => food_cat.id,
        "amount" => 5_000,
        "month" => 4,
        "year" => 2026,
      })
      expect(result[:proposal][:kind]).to eq("create_budget")
      expect(result[:proposal][:amount]).to eq(5_000.0)
    end

    it "rejects non-positive amounts" do
      expect {
        described_class.new(user).call({ "category_id" => food_cat.id, "amount" => 0 })
      }.to raise_error(Ai::Tools::Base::ToolError)
    end

    it "rejects when no category can be resolved" do
      expect {
        described_class.new(user).call({ "category_name" => "nonexistent", "amount" => 1_000 })
      }.to raise_error(Ai::Tools::Base::ToolError)
    end
  end

  describe Ai::Tools::ProposeCreateCategoryRule do
    it "mints a proposal pairing pattern + category" do
      result = described_class.new(user).call({
        "category_id" => food_cat.id,
        "pattern" => "swiggy",
      })
      expect(result[:proposal][:kind]).to eq("create_category_rule")
      expect(result[:proposal][:pattern]).to eq("swiggy")
    end

    it "rejects very short patterns" do
      expect {
        described_class.new(user).call({ "category_id" => food_cat.id, "pattern" => "ab" })
      }.to raise_error(Ai::Tools::Base::ToolError)
    end
  end

  describe Ai::Tools::ProposeRecategorize do
    let(:bank) { make_bank_account(user: user) }
    let(:statement) { make_statement(bank_account: bank) }

    it "rejects empty transaction id lists" do
      expect {
        described_class.new(user).call({ "transaction_ids" => [], "category_id" => food_cat.id })
      }.to raise_error(Ai::Tools::Base::ToolError)
    end

    it "filters non-owned transaction ids before signing the proposal" do
      mine = make_transaction(statement: statement, date: Date.new(2026, 4, 5))
      other_user = make_user
      other_bank = make_bank_account(user: other_user)
      other_statement = make_statement(bank_account: other_bank)
      not_mine = make_transaction(statement: other_statement, date: Date.new(2026, 4, 5))

      result = described_class.new(user).call({
        "transaction_ids" => [mine.id, not_mine.id],
        "category_id" => food_cat.id,
      })
      payload = Ai::ProposalVerifier.verify(result[:proposal][:token], user: user)
      expect(payload[:args][:transaction_ids]).to contain_exactly(mine.id)
    end
  end
end

RSpec.describe Ai::ProposalVerifier, type: :service do
  let(:user) { make_user }

  it "rejects tampered tokens" do
    token = described_class.sign(user, "create_category", { name: "Foo" })
    tampered = token + "x"
    expect { described_class.verify(tampered, user: user) }.to raise_error(described_class::InvalidProposalError)
  end

  it "rejects tokens issued to a different user" do
    other = make_user
    token = described_class.sign(user, "create_category", { name: "Foo" })
    expect { described_class.verify(token, user: other) }.to raise_error(described_class::InvalidProposalError)
  end

  it "rejects unknown proposal kinds at sign time" do
    expect { described_class.sign(user, "delete_everything", {}) }.to raise_error(ArgumentError)
  end
end

RSpec.describe Ai::ProposalExecutor, type: :service do
  let(:user) { make_user }
  subject(:executor) { described_class.new(user) }

  describe "create_category" do
    it "creates a new category from a signed proposal" do
      token = Ai::ProposalVerifier.sign(user, "create_category", { name: "Subscriptions", color: "#abcdef" })
      result = executor.call(token)
      expect(result[:kind]).to eq("create_category")
      expect(user.categories.where(name: "Subscriptions")).to exist
    end
  end

  describe "create_budget" do
    it "creates a budget for the user's category" do
      cat = user.categories.first
      token = Ai::ProposalVerifier.sign(user, "create_budget", {
        category_id: cat.id, amount: 4_500, month: 4, year: 2026,
      })
      result = executor.call(token)
      expect(result[:kind]).to eq("create_budget")
      expect(user.budgets.where(category: cat, month: 4, year: 2026)).to exist
    end
  end

  describe "create_category_rule" do
    it "creates a rule for the user's category" do
      cat = user.categories.first
      token = Ai::ProposalVerifier.sign(user, "create_category_rule", {
        category_id: cat.id, pattern: "swiggy",
      })
      executor.call(token)
      expect(user.category_rules.where(merchant_pattern: "swiggy")).to exist
    end
  end

  describe "recategorize_transactions" do
    it "updates owned transactions to the new category in a single transaction" do
      bank = make_bank_account(user: user)
      statement = make_statement(bank_account: bank)
      t1 = make_transaction(statement: statement, date: Date.new(2026, 4, 10))
      t2 = make_transaction(statement: statement, date: Date.new(2026, 4, 11))
      cat = user.categories.first

      token = Ai::ProposalVerifier.sign(user, "recategorize_transactions", {
        transaction_ids: [t1.id, t2.id],
        category_id: cat.id,
      })
      result = executor.call(token)
      expect(result[:updated_count]).to eq(2)
      expect(t1.reload.category).to eq(cat)
      expect(t2.reload.category).to eq(cat)
    end
  end
end
