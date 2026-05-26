# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentSuggestionAcceptorService, type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:stmt) { make_statement(bank_account: bank, status: "parsed") }

  def make_suggestion(amount:, kind:, asset_class: "stock", account_name: "Broker account")
    tx = make_transaction(
      statement: stmt,
      description: "UPI-MUTUAL FUNDS ICCL-GROWW",
      amount: amount,
      transaction_type: "debit",
    )
    InvestmentSuggestion.create!(
      user: user,
      source_transaction: tx,
      suggested_asset_class: asset_class,
      suggested_kind: kind,
      suggested_account_name: account_name,
      status: "pending",
    )
  end

  describe "regression: 'buy' kind populates invested_amount (was zero with 'transfer_out')" do
    it "increments the holding's invested_amount by the transaction amount" do
      sugg = make_suggestion(amount: 5_000, kind: "buy")

      described_class.new(user, sugg).call

      holding = user.investment_holdings.first
      expect(holding).to be_present
      expect(holding.invested_amount.to_f).to eq(5_000.0)
    end

    it "aggregates multiple accepted suggestions on the same holding correctly" do
      # Same Groww account → same holding (since the description prefix matches).
      # Acceptor uses tx.description for holding name, so we use identical
      # descriptions to verify aggregation works when names match.
      tx1 = make_transaction(statement: stmt, description: "GROWW ICCL", amount: 5_000)
      tx2 = make_transaction(statement: stmt, description: "GROWW ICCL", amount: 3_000)
      [tx1, tx2].each do |tx|
        sugg = InvestmentSuggestion.create!(
          user: user, source_transaction: tx,
          suggested_asset_class: "stock", suggested_kind: "buy",
          suggested_account_name: "Broker account", status: "pending",
        )
        described_class.new(user, sugg).call
      end

      holding = user.investment_holdings.first
      expect(holding.invested_amount.to_f).to eq(8_000.0)
    end
  end

  describe "folio-aware deduplication (StatementParsing::PortfolioExtractor handoff)" do
    # When the ICICI consolidated statement is uploaded, PortfolioExtractor
    # creates a canonical PPF / FD / RD holding (with `folio` populated)
    # from the page-1 passbook tables. Later, InvestmentDetectionService
    # scans the savings-side debits ("Trf to PPF 000418336506",
    # "TRF TO FD no. 153913018495") and produces suggestions. The acceptor
    # MUST attach those accepted suggestions to the canonical holding
    # rather than forking a parallel "Trf to PPF 000418336506" holding —
    # otherwise the user sees doubled PPF balances and the suggestion-to-
    # holding link breaks.
    it "attaches a Trf to PPF acceptance to the existing PPF holding by folio" do
      canonical = user.investment_holdings.create!(
        investment_account: user.investment_accounts.create!(
          name: "ICICI PPF", account_kind: "ppf"
        ),
        asset_class: "ppf",
        name: "ICICI PPF 000418336506",
        folio: "000418336506",
        invested_amount: 3_83_025.00,
      )

      tx = make_transaction(
        statement: stmt,
        description: "Trf to PPF 000418336506",
        amount: 2_000,
        transaction_type: "debit",
      )
      sugg = InvestmentSuggestion.create!(
        user: user, source_transaction: tx,
        suggested_asset_class: "ppf", suggested_kind: "contribution",
        suggested_account_name: "PPF", status: "pending",
      )

      expect { described_class.new(user, sugg).call }
        .not_to change { user.investment_holdings.count }

      canonical.reload
      expect(canonical.invested_amount.to_f).to eq(3_85_025.00) # +2,000 contribution
      expect(canonical.investment_transactions.count).to eq(1)
    end

    it "extracts the folio from 'TRF TO FD no. 153913018495' style descriptions" do
      canonical = user.investment_holdings.create!(
        investment_account: user.investment_accounts.create!(
          name: "ICICI FD", account_kind: "fd"
        ),
        asset_class: "fd",
        name: "ICICI FD 153913018495",
        folio: "153913018495",
        invested_amount: 50_000.00,
      )

      tx = make_transaction(
        statement: stmt,
        description: "TRF TO FD no. 153913018495",
        amount: 50_000,
        transaction_type: "debit",
      )
      sugg = InvestmentSuggestion.create!(
        user: user, source_transaction: tx,
        suggested_asset_class: "fd", suggested_kind: "buy",
        suggested_account_name: "Fixed deposits", status: "pending",
      )

      expect { described_class.new(user, sugg).call }
        .not_to change { user.investment_holdings.count }

      canonical.reload
      expect(canonical.invested_amount.to_f).to eq(1_00_000.00)
    end

    it "falls back to creating a new holding when description carries no folio" do
      tx = make_transaction(
        statement: stmt,
        description: "GROWW ICCL",
        amount: 5_000,
        transaction_type: "debit",
      )
      sugg = InvestmentSuggestion.create!(
        user: user, source_transaction: tx,
        suggested_asset_class: "stock", suggested_kind: "buy",
        suggested_account_name: "Broker account", status: "pending",
      )

      expect { described_class.new(user, sugg).call }
        .to change { user.investment_holdings.count }.by(1)
    end
  end

  describe "outflow kinds (kept for completeness)" do
    it "'sell' decrements invested_amount, floored at 0" do
      # First build up some invested_amount, then a sell.
      buy = make_suggestion(amount: 5_000, kind: "buy")
      described_class.new(user, buy).call

      sell = make_suggestion(amount: 2_000, kind: "sell")
      described_class.new(user, sell).call

      holding = user.investment_holdings.first
      expect(holding.invested_amount.to_f).to eq(3_000.0)
    end
  end
end
