# frozen_string_literal: true

require "rails_helper"

RSpec.describe BankAccountsController, type: :request do
  let(:user) { make_user }

  before { sign_in(user) }

  describe "GET /bank_accounts" do
    it "responds 200 and renders the BankAccounts/Index page" do
      get bank_accounts_path, headers: { "X-Inertia" => "true" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["component"]).to eq("BankAccounts/Index")
    end

    it "regression: statements are eager-loaded (no N+1 across accounts)" do
      # Three bank accounts, each with two statements. Without includes(:statements)
      # this would trigger 3 extra statements queries.
      3.times do |i|
        bank = make_bank_account(user: user, last_four: format("%04d", i))
        2.times { |m| bank.statements.create!(month: m + 1, year: 2026, status: "parsed") }
      end

      statement_loads = 0
      subscriber = ->(_name, _started, _finished, _id, payload) {
        sql = payload[:sql].to_s
        # Match the per-bank-account follow-up loads (WHERE bank_account_id = ?)
        next unless sql.match?(/FROM\s+"statements"/i)
        next if sql.match?(/IN\s*\(/) # the grouped includes() query
        statement_loads += 1
      }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get bank_accounts_path, headers: { "X-Inertia" => "true" }
      end

      expect(statement_loads).to eq(0),
        "expected no per-bank-account statement queries (got #{statement_loads}); includes(:statements) regressed"
    end
  end
end
