# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ai::Tools read-only tools", type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, month: 4, year: 2026) }
  let(:food_cat) { user.categories.find_by(name: "Food & Dining") }

  before do
    make_transaction(statement: statement, date: Date.new(2026, 4, 5), description: "SALARY APRIL 2026",
                     amount: 100_000, transaction_type: "credit")
    make_transaction(statement: statement, date: Date.new(2026, 4, 10), description: "SWIGGY ORDER",
                     amount: 350, transaction_type: "debit", category: food_cat, merchant: "Swiggy")
    make_transaction(statement: statement, date: Date.new(2026, 4, 12), description: "AMAZON ORDER",
                     amount: 1_200, transaction_type: "debit")
  end

  describe Ai::Tools::ListCategories do
    it "returns all of the user's categories" do
      result = described_class.new(user).call({})
      expect(result[:count]).to eq(user.categories.count)
      expect(result[:categories].map { |c| c[:name] }).to include("Food & Dining")
    end
  end

  describe Ai::Tools::SearchTransactions do
    it "matches by description (case-insensitive substring)" do
      result = described_class.new(user).call({ "query" => "swiggy", "months_back" => 12 })
      expect(result[:returned]).to eq(1)
      expect(result[:transactions].first[:description]).to match(/SWIGGY/i)
    end

    it "filters by transaction type" do
      result = described_class.new(user).call({ "query" => "a", "type" => "credit", "months_back" => 12 })
      expect(result[:transactions]).to all(include(type: "credit"))
    end

    it "requires a query parameter" do
      expect { described_class.new(user).call({}) }
        .to raise_error(Ai::Tools::Base::ToolError, /query/i)
    end
  end

  describe Ai::Tools::UncategorizedTransactions do
    it "returns only uncategorized debit transactions" do
      result = described_class.new(user).call({ "months_back" => 12 })
      expect(result[:count]).to eq(1)
      expect(result[:transactions].first[:description]).to match(/AMAZON/i)
    end
  end

  describe Ai::Tools::TopMerchants do
    it "groups & sums debit amounts per merchant" do
      result = described_class.new(user).call({ "months_back" => 12 })
      expect(result[:top_merchants]).to be_an(Array)
      expect(result[:top_merchants]).to all(include(:merchant, :total))
    end
  end

  describe Ai::Tools::MonthlySummary do
    it "computes income, expense and net" do
      result = described_class.new(user).call({ "months_back" => 12 })
      expect(result[:income]).to eq(100_000.0)
      expect(result[:expense]).to eq(1_550.0)
      expect(result[:net]).to eq(98_450.0)
    end
  end

  describe Ai::Tools::RecurringTransactions do
    it "returns only is_recurring=true rows" do
      result = described_class.new(user).call({ "months_back" => 12 })
      expect(result[:recurring]).to be_an(Array)
      expect(result[:recurring]).to be_empty
    end
  end

  describe Ai::Tools::BudgetStatus do
    let!(:budget) do
      user.budgets.create!(category: food_cat, amount: 5_000, month: 4, year: 2026)
    end

    it "returns budget rows for the requested month" do
      result = described_class.new(user).call({ "month" => 4, "year" => 2026 })
      expect(result[:budgets]).to be_an(Array)
      expect(result[:budgets].first).to include(:category, :budget, :spent, :remaining)
    end
  end

  describe Ai::Tools::CreditCardSummary do
    it "lists credit cards belonging to the user" do
      user.credit_cards.create!(name: "HDFC Regalia", rewards_structure: { "base_reward" => { "rate" => 1 } })
      result = described_class.new(user).call({})
      expect(result[:count]).to eq(1)
      expect(result[:cards].first[:name]).to eq("HDFC Regalia")
    end
  end

  describe Ai::Tools::HoldingsSnapshot do
    it "returns serialized holdings with invested totals" do
      account = make_investment_account(user: user)
      make_investment_holding(user: user, investment_account: account, name: "INFY", invested_amount: 5_000)
      result = described_class.new(user).call({})
      expect(result[:count]).to eq(1)
      expect(result[:total_invested]).to eq(5_000.0)
    end
  end

  describe Ai::Tools::NetWorth do
    it "delegates to NetWorthService" do
      fake_payload = { total_assets: 100, total_liabilities: 0, net_worth: 100 }
      expect_any_instance_of(NetWorthService).to receive(:call).and_return(fake_payload)
      expect(described_class.new(user).call({})).to eq(fake_payload)
    end
  end

  describe Ai::Tools::BestCardForPurchase do
    it "delegates to BestCardForPurchaseService" do
      fake = { recommended_card: "HDFC Regalia", reward_rate: 4 }
      expect(BestCardForPurchaseService).to receive(:new).with(user).and_return(double(call: fake))
      result = described_class.new(user).call({ "category" => "Dining", "merchant" => "Swiggy", "amount" => 500 })
      expect(result).to eq(fake)
    end
  end

  describe Ai::Tools::AisReconciliation do
    it "delegates to AisReconciliationService and surfaces financial_year_label" do
      fake = {
        financial_year_label: "2026-27",
        has_ais: false,
        has_form16: false,
        rows: [],
      }
      expect(AisReconciliationService).to receive(:new)
        .with(user, financial_year_start: 2026).and_return(double(call: fake))
      result = described_class.new(user).call({ "financial_year_start" => 2026 })
      expect(result).to include(
        financial_year: "2026-27",
        has_ais: false,
        has_form16: false,
        rows: []
      )
    end
  end

  describe Ai::Tools::ItrReadiness do
    it "delegates to ItrReadinessService and remaps the checklist into gaps" do
      fake = {
        financial_year_label: "2026-27",
        readiness_pct: 50,
        suggested_itr_form: { form: "ITR-1" },
        income: 100_000,
        salary_estimate: 95_000,
        business_income_estimate: 0,
        investment_summary: { holdings_count: 0 },
        checklist: [
          { id: "x", label: "Upload Form 16", done: false },
          { id: "y", label: "Statements", done: true },
        ],
        documents: { "form16" => { uploaded: false, extracted: false } },
      }
      expect(ItrReadinessService).to receive(:new)
        .with(user, financial_year_start: 2026).and_return(double(call: fake))

      result = described_class.new(user).call({ "financial_year_start" => 2026 })
      expect(result[:readiness_pct]).to eq(50)
      expect(result[:suggested_form]).to eq({ form: "ITR-1" })
      expect(result[:checklist_gaps]).to eq(["Upload Form 16"])
    end
  end

  describe Ai::Tools::CapitalGains do
    it "delegates to CapitalGainsSummaryService and truncates rows by limit" do
      rows = Array.new(60) { |i| { date: Date.today, amount: i, gain_type: "STCG" } }
      fake = { rows: rows, document_stcg: 0, document_ltcg: 0 }
      expect(CapitalGainsSummaryService).to receive(:new).and_return(double(call: fake))

      result = described_class.new(user).call({ "financial_year_start" => 2026, "limit" => 10 })
      expect(result[:rows].size).to eq(10)
      expect(result[:total_rows]).to eq(60)
    end
  end

  describe Ai::Tools::RegimeCompare do
    it "delegates to TaxRegimeCompareService" do
      fake = { old_regime: { total: 100 }, new_regime: { total: 80 }, likely_better: "new", difference: 20 }
      expect(TaxRegimeCompareService).to receive(:new).and_return(double(call: fake))
      result = described_class.new(user).call({ "financial_year_start" => 2026 })
      expect(result).to include(:old_regime, :new_regime, :likely_better)
    end
  end

  describe Ai::Tools::TaxSavings do
    it "delegates to TaxSavingsAdvisorService and surfaces ranked recommendations" do
      fake = {
        financial_year_label: "2026-27",
        regime_recommendation: "new",
        regime_savings: 12_000,
        marginal_rate_used: 0.20,
        old_regime_relevant: true,
        total_potential_saving: 45_000,
        recommendations: [
          { section: "80C", label: "Section 80C", priority: :high, potential_saving: 30_000 },
          { section: "80D", label: "Section 80D", priority: :medium, potential_saving: 5_000 },
        ],
        disclaimer: "advisory only",
      }
      expect(TaxSavingsAdvisorService).to receive(:new).with(user, financial_year_start: 2026).and_return(double(call: fake))

      result = described_class.new(user).call({ "financial_year_start" => 2026 })
      expect(result[:financial_year]).to eq("2026-27")
      expect(result[:total_potential_saving]).to eq(45_000)
      expect(result[:recommendations].size).to eq(2)
      expect(result[:old_regime_relevant]).to be true
    end

    it "is registered in the ITR tool list" do
      expect(Ai::Tools::Registry.for(mode: 'itr')).to include(Ai::Tools::TaxSavings)
    end
  end
end
