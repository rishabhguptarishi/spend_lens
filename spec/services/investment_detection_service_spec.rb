# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentDetectionService, type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:stmt) { make_statement(bank_account: bank, status: "parsed") }

  def matched_kind_for(description)
    tx = make_transaction(statement: stmt, description: description, amount: 5000, transaction_type: "debit")
    described_class.match_rule(tx, user: user)&.[](:kind)
  end

  describe "broker rule (regression: was 'transfer_out' which left invested_amount at 0)" do
    it "classifies Groww UPI debits as 'buy' (inflow into investments)" do
      expect(matched_kind_for("UPI-MUTUAL FUNDS ICCL-GROWW.ICCL1.BRK@VALIDHDFC")).to eq("buy")
    end

    it "classifies Zerodha as 'buy'" do
      expect(matched_kind_for("UPI/ZERODHA BROKING 1234")).to eq("buy")
    end

    it "classifies Upstox as 'buy'" do
      expect(matched_kind_for("NEFT-UPSTOX SECURITIES")).to eq("buy")
    end
  end

  describe "other rules remain unchanged" do
    it "mutual fund (CAMS) → buy" do
      expect(matched_kind_for("NEFT CAMS XYZ")).to eq("buy")
    end

    it "NPS → contribution" do
      expect(matched_kind_for("NSDL NPS CONTRIBUTION")).to eq("contribution")
    end

    it "dividend → dividend" do
      expect(matched_kind_for("INFY DIVIDEND CR")).to eq("dividend")
    end
  end

  describe "Indian bank-code rules (MOB-TD / FRSB / AMC SIPs / sweeps)" do
    it "MOB-TD (mobile term deposit) → fd / buy" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "MOB-TD/926040058278575/RISHABH GUPTA", amount: 50000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "fd", kind: "buy", account_name: "Fixed deposits")
    end

    it "FRSB (RBI Floating Rate Savings Bond) → bond / buy" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "FRSB/917010081786930/RISHABH GUPTA", amount: 100000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "bond", kind: "buy", account_name: "RBI Floating Rate Savings Bond")
    end

    it "AXISDIRECT broker → stock / buy" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "AXISDIRECT/858977X/21-08-2025/12:08", amount: 885, transaction_type: "debit"))
      expect(rule).to include(asset_class: "stock", kind: "buy", account_name: "Broker account")
    end

    it "Canara Robeco MF SIP → mutual_fund / sip" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "Canara Robeco E/133826853/ETGP", amount: 1000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "mutual_fund", kind: "sip")
    end

    it "MIRAE ASSET MF SIP → mutual_fund / sip" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "MIRAE ASSET ELS/134500597/TSRG", amount: 1000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "mutual_fund", kind: "sip")
    end

    it "AUTOSWEEP → fd / buy" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "AUTOSWEEP TO FD 12345", amount: 50000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "fd", kind: "buy")
    end
  end

  describe "ICICI consolidated-statement rules" do
    it "TRF TO FD no. … → fd / buy" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "TRF TO FD no. 153913018495", amount: 50000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "fd", kind: "buy", account_name: "Fixed deposits")
    end

    it "To RD Ac no … → rd / contribution" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "To RD Ac no 153925003301", amount: 5000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "rd", kind: "contribution", account_name: "Recurring deposits")
    end

    it "Dr Tran For Funding A/c … → rd / contribution (RD funding via NB)" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "Dr Tran For Funding A/c 153925003301", amount: 5000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "rd", kind: "contribution")
    end

    it "Trf to PPF … → ppf / contribution (already matched by existing ppf rule)" do
      rule = described_class.match_rule(make_transaction(statement: stmt, description: "Trf to PPF 000418336506", amount: 2000, transaction_type: "debit"))
      expect(rule).to include(asset_class: "ppf", kind: "contribution")
    end
  end

  describe "direction-aware kinds (kind_credit override)" do
    let(:service) { described_class.new(user) }

    it "MOB-TD as DEBIT → 'buy' (FD creation)" do
      tx = make_transaction(statement: stmt, description: "MOB-TD/12345/USER", amount: 50000, transaction_type: "debit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("buy")
    end

    it "MOB-TD as CREDIT → 'maturity' (FD payout back to savings)" do
      tx = make_transaction(statement: stmt, description: "MOB-TD/12345/USER MATURITY", amount: 50000, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("maturity")
    end

    it "FRSB credit → 'maturity' (bond redemption)" do
      tx = make_transaction(statement: stmt, description: "FRSB/12345/USER", amount: 100000, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("maturity")
    end

    it "Broker credit → 'sell' (proceeds returning to savings)" do
      tx = make_transaction(statement: stmt, description: "ZERODHA BROKING PAYOUT", amount: 25000, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("sell")
    end

    it "legacy rule without kind_credit still works (dividend stays 'dividend')" do
      tx = make_transaction(statement: stmt, description: "INFY DIVIDEND CR", amount: 1500, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("dividend")
    end

    it "interest credit (FD interest) stays 'interest' regardless of direction" do
      tx = make_transaction(statement: stmt, description: "FD INT CR 12345", amount: 875, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("interest")
    end

    # Phase-0 G9: PPF/NPS rules now declare kind_credit: 'maturity' explicitly
    # so a partial PPF withdrawal or NPS payout returning to savings doesn't
    # silently get mis-classified as a contribution (which was the previous
    # implicit fallback behaviour).
    it "PPF debit → 'contribution' (normal flow)" do
      tx = make_transaction(statement: stmt, description: "Trf to PPF 000418336506", amount: 2000, transaction_type: "debit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("contribution")
    end

    it "PPF credit → 'maturity' (rare partial withdrawal / maturity)" do
      tx = make_transaction(statement: stmt, description: "PPF Withdrawal Credit", amount: 50000, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("maturity")
    end

    it "NPS credit → 'maturity' (NPS payout to savings)" do
      tx = make_transaction(statement: stmt, description: "Protean NPS withdrawal", amount: 100000, transaction_type: "credit")
      rule = described_class.match_rule(tx)
      expect(service.resolve_kind(rule, tx)).to eq("maturity")
    end
  end

  describe "#scan_transactions! creates suggestions with direction-aware kinds" do
    let(:service) { described_class.new(user) }

    it "creates an FD 'buy' suggestion for a MOB-TD debit" do
      tx = make_transaction(statement: stmt, description: "MOB-TD/12345/USER", amount: 50000, transaction_type: "debit")

      expect { service.scan_transactions!(transaction_ids: [tx.id]) }.to change(InvestmentSuggestion, :count).by(1)

      sug = InvestmentSuggestion.last
      expect(sug.suggested_asset_class).to eq("fd")
      expect(sug.suggested_kind).to eq("buy")
    end

    it "creates a bond 'maturity' suggestion for an FRSB credit" do
      tx = make_transaction(statement: stmt, description: "FRSB/12345/USER REDEMPTION", amount: 100000, transaction_type: "credit")

      service.scan_transactions!(transaction_ids: [tx.id])

      sug = InvestmentSuggestion.find_by(source_transaction: tx)
      expect(sug.suggested_asset_class).to eq("bond")
      expect(sug.suggested_kind).to eq("maturity")
    end

    it "is idempotent — re-scanning doesn't duplicate suggestions" do
      tx = make_transaction(statement: stmt, description: "MOB-TD/12345/USER", amount: 50000, transaction_type: "debit")

      expect { service.scan_transactions! }.to change(InvestmentSuggestion, :count).by(1)
      expect { service.scan_transactions! }.not_to change(InvestmentSuggestion, :count)
    end
  end
end
