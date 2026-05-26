# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCategorizationService, type: :service do
  let!(:user) { User.create!(email: "test@example.com", password: "password123") }
  let(:service) { described_class.new(user) }

  describe "#categorize" do
    let(:food_category) { user.categories.find_by(name: "Food & Dining") }
    let(:transport_category) { user.categories.find_by(name: "Transport") }

    context "when a matching user rule exists" do
      before do
        user.category_rules.create!(
          merchant_pattern: "swiggy",
          category: food_category
        )
      end

      it "returns the category matched by the rule" do
        result = service.categorize("SWIGGY INDIA PVT LTD")
        expect(result).to eq(food_category)
      end
    end

    context "when using AI categorization" do
      before do
        # Enable AI categorization in user preferences
        allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(true)
      end

      it "uses the AI generated suggestion matching an existing category" do
        allow(AiClient).to receive(:chat).and_return("Food & Dining")

        result = service.categorize("Some random cafe transaction")
        expect(result).to eq(food_category)
      end

      it "creates a new category if the AI suggests one that does not exist" do
        allow_any_instance_of(UserPreference).to receive(:ai_create_categories?).and_return(true)
        allow(AiClient).to receive(:chat).and_return("Education")

        result = service.categorize("Udemy purchase")
        expect(result.name).to eq("Education")
        expect(user.categories.find_by(name: "Education")).to be_present
      end

      it "does not create a new category if auto-create is disabled, returning default" do
        allow_any_instance_of(UserPreference).to receive(:ai_create_categories?).and_return(false)
        allow(AiClient).to receive(:chat).and_return("Education")

        result = service.categorize("Udemy purchase")
        expect(result.name).to eq("Uncategorized")
      end
    end

    context "when AI categorization is down or errors" do
      before do
        allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(true)
        allow(AiClient).to receive(:chat).and_raise(RuntimeError, "AI service down")
      end

      it "falls back to keyword-based parsing (e.g. zomato)" do
        result = service.categorize("ZOMATO ONLINE ORDER")
        expect(result).to eq(food_category)
      end

      it "returns Uncategorized if no keyword matches" do
        result = service.categorize("Random unknown merchant transaction")
        expect(result.name).to eq("Uncategorized")
      end
    end

    context "when AI categorization is disabled" do
      before do
        allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(false)
      end

      it "checks keyword fallback first" do
        result = service.categorize("UBER TRIP")
        expect(result).to eq(transport_category)
      end
    end
  end

  describe "Indian bank-code shortcut rules (BANK_CODE_RULES)" do
    let(:investments_category) { user.categories.find_or_create_by!(name: "Investments", color: "#10B981") }
    let(:interest_category)    { user.categories.find_or_create_by!(name: "Interest Income", color: "#06B6D4") }
    let(:transfer_category)    { user.categories.find_by(name: "Transfer") }

    before do
      investments_category
      interest_category
      allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(true)
      allow_any_instance_of(UserPreference).to receive(:auto_categorize_statements?).and_return(true)
    end

    it "routes MOB-TD (Mobile Term Deposit) to Investments without asking AI" do
      # Critical regression: AI used to mis-categorize this as Transfer
      # because of the "/RISHABH GUPTA" customer-name suffix.
      ai_called = false
      allow(AiClient).to receive(:chat) { ai_called = true; "Transfer" }

      result = service.categorize("MOB-TD/926040058278575/RISHABH GUPTA")

      expect(result).to eq(investments_category)
      expect(ai_called).to be false
    end

    it "routes MOB-FD and MOB-RD the same way" do
      expect(service.categorize("MOB-FD/12345/USERNAME")).to eq(investments_category)
      expect(service.categorize("MOB-RD/67890/USERNAME")).to eq(investments_category)
    end

    it "routes FRSB (RBI Floating Rate Savings Bond) to Investments" do
      # FRSB = the Reserve Bank of India's 7.15% Floating Rate Savings
      # Bond (a sovereign retail-investment product). Bank statements
      # carry it as e.g. "FRSB/917010081786930/RISHABH GUPTA" — without
      # this rule the trailing customer name fools AI into "Transfer".
      expect(service.categorize("FRSB/917010081786930/RISHABH GUPTA")).to eq(investments_category)
    end

    it "routes AUTOSWEEP / REV SWEEP / SWEEP TRF to Investments" do
      expect(service.categorize("AUTOSWEEP TO FD")).to eq(investments_category)
      expect(service.categorize("REV SWEEP FROM FD")).to eq(investments_category)
      expect(service.categorize("SWEEP TRF 12345")).to eq(investments_category)
    end

    it "routes broker keywords (AXISDIRECT/ZERODHA/GROWW) to Investments" do
      expect(service.categorize("AXISDIRECT/858977X/21-08-2025/12:08")).to eq(investments_category)
      expect(service.categorize("ZERODHA BROKING")).to eq(investments_category)
      expect(service.categorize("GROWW INVEST")).to eq(investments_category)
    end

    it "routes mutual-fund AMC SIPs (Canara Robeco, MIRAE ASSET, Nippon India, ...) to Investments" do
      expect(service.categorize("Canara Robeco E/133826853/ETGP")).to eq(investments_category)
      expect(service.categorize("MIRAE ASSET ELS/134500597/TSRG")).to eq(investments_category)
      expect(service.categorize("NIPPON INDIA SIP")).to eq(investments_category)
    end

    it "routes Int.Pd interest credits to Interest Income" do
      expect(service.categorize("SB:917010081786930:Int.Pd:01-04-2025 to 30-06-2025")).to eq(interest_category)
    end

    it "falls through to AI when no bank code matches" do
      allow(AiClient).to receive(:chat).and_return("Food & Dining")
      food = user.categories.find_by(name: "Food & Dining")

      result = service.categorize("Random merchant ABC123")

      expect(result).to eq(food)
    end

    it "user rules still win over bank-code shortcuts" do
      manual = user.categories.find_or_create_by!(name: "Manual Override", color: "#000")
      user.category_rules.create!(merchant_pattern: "mob-td", category: manual)

      expect(service.categorize("MOB-TD/12345/USERNAME")).to eq(manual)
    end

    it "does not create the bank-code category if ai_create_categories? is off and it does not exist" do
      allow_any_instance_of(UserPreference).to receive(:ai_create_categories?).and_return(false)
      allow(AiClient).to receive(:chat).and_return("Food & Dining")
      food = user.categories.find_by(name: "Food & Dining")
      user.categories.where(name: "Investments").destroy_all

      # Falls through to AI, which returns Food & Dining
      result = service.categorize("MOB-TD/12345/USER")
      expect(result).to eq(food)
    end
  end

  describe "#learn" do
    let(:shopping_category) { user.categories.find_by(name: "Shopping") }

    it "creates a category rule when a user manually corrects a category" do
      expect {
        service.learn("AMAZON PAY INDIA", category: shopping_category)
      }.to change { user.category_rules.count }.by(1)

      rule = user.category_rules.last
      expect(rule.merchant_pattern).to eq("amazon")
      expect(rule.category).to eq(shopping_category)
    end
  end

  describe "per-instance memoization (regression for N+1 categorizer queries)" do
    let(:food) { user.categories.find_by(name: "Food & Dining") }

    it "loads category_rules at most once across many categorize calls" do
      user.category_rules.create!(merchant_pattern: "swiggy", category: food)

      callable = service
      # Use a single SELECT-style query log to count category_rules lookups.
      rule_queries = 0
      counter = ->(_name, _started, _finished, _id, payload) {
        sql = payload[:sql].to_s
        rule_queries += 1 if sql.include?('"category_rules"') && sql.match?(/SELECT/i)
      }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        5.times { callable.categorize("SWIGGY ORDER") }
      end

      expect(rule_queries).to eq(1), "expected category_rules to be loaded once across 5 categorize calls, got #{rule_queries}"
    end

    it "loads category list at most once when AI categorization is in use" do
      allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(true)
      allow(AiClient).to receive(:chat).and_return("Food & Dining")

      cat_queries = 0
      counter = ->(_name, _started, _finished, _id, payload) {
        sql = payload[:sql].to_s
        cat_queries += 1 if sql.include?('"categories"') && sql.match?(/SELECT/i)
      }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        5.times { service.categorize("Random text") }
      end

      # One initial categories load is plenty for repeated AI-driven categorize calls.
      expect(cat_queries).to be <= 1
    end

    it "remembers newly-created categories so they aren't re-created on subsequent calls" do
      allow_any_instance_of(UserPreference).to receive(:ai_categorize?).and_return(true)
      allow_any_instance_of(UserPreference).to receive(:ai_create_categories?).and_return(true)
      allow(AiClient).to receive(:chat).and_return("Subscriptions")

      expect {
        3.times { service.categorize("Some online subscription") }
      }.to change { user.categories.where(name: "Subscriptions").count }.from(0).to(1)
    end
  end
end
