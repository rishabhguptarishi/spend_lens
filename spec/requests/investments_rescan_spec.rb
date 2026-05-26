# frozen_string_literal: true

require "rails_helper"

# Covers POST /investments/rescan — re-evaluates all bank transactions
# against the current InvestmentDetectionService rules. Critical when
# new rules ship (MOB-TD / FRSB / AMC SIPs) so transactions imported
# under the previous rule set get retroactively surfaced as portfolio
# candidates.
RSpec.describe "POST /investments/rescan", type: :request do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:stmt) { make_statement(bank_account: bank, status: "parsed") }

  before { sign_in(user) }

  it "creates suggestions for previously-uploaded MOB-TD transactions" do
    make_transaction(statement: stmt, description: "MOB-TD/926040058278575/RISHABH GUPTA",
                     amount: 50_000, transaction_type: "debit")
    make_transaction(statement: stmt, description: "FRSB/917010081786930/RISHABH GUPTA",
                     amount: 100_000, transaction_type: "debit")
    make_transaction(statement: stmt, description: "Canara Robeco E/133826853/ETGP",
                     amount: 1_000, transaction_type: "debit")

    expect { post investments_rescan_path }.to change(InvestmentSuggestion, :count).by(3)
    expect(response).to redirect_to(investments_suggestions_path)
    follow_redirect!
    expect(response.body).to include("Found 3 new investment suggestions")
  end

  it "is idempotent — running twice doesn't duplicate" do
    make_transaction(statement: stmt, description: "MOB-TD/12345/USER",
                     amount: 50_000, transaction_type: "debit")

    expect { post investments_rescan_path }.to change(InvestmentSuggestion, :count).by(1)
    expect { post investments_rescan_path }.not_to change(InvestmentSuggestion, :count)
    follow_redirect!
    expect(response.body).to include("No new suggestions found")
  end

  it "only scopes to the current user's transactions" do
    other_user = make_user(email: "other@example.com")
    other_stmt = make_statement(bank_account: make_bank_account(user: other_user), status: "parsed")
    make_transaction(statement: other_stmt, description: "MOB-TD/99999/OTHER USER",
                     amount: 50_000, transaction_type: "debit")

    expect { post investments_rescan_path }.not_to change(InvestmentSuggestion, :count)
  end
end
