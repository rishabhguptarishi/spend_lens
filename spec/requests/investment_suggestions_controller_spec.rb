# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvestmentSuggestionsController, type: :request do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:stmt) { make_statement(bank_account: bank, status: "parsed") }

  def make_suggestion(status: "pending")
    tx = make_transaction(statement: stmt, description: "ZERODHA")
    InvestmentSuggestion.create!(
      user: user,
      source_transaction: tx,
      suggested_asset_class: "stock",
      suggested_kind: "buy",
      status: status,
    )
  end

  before { sign_in(user) }

  describe "POST /investment_suggestions/accept_all" do
    it "regression: does NOT 404 when there are no suggestions (collection action, no :id needed)" do
      # Previously `before_action :set_suggestion` ran on every action, causing
      # accept_all to ActiveRecord::RecordNotFound when no :id param is sent.
      post accept_all_investment_suggestions_path
      # Phase 4: redirect target moved to /investments/suggestions so the
      # user stays on the bucket page after a bulk-accept (instead of
      # being dumped back to the portfolio).
      expect(response).to redirect_to(investments_suggestions_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "accepts all pending suggestions and skips already-resolved ones" do
      pending_1 = make_suggestion(status: "pending")
      pending_2 = make_suggestion(status: "pending")
      already_rejected = make_suggestion(status: "rejected")

      allow_any_instance_of(InvestmentSuggestionAcceptorService).to receive(:call) do |svc|
        svc.instance_variable_get(:@suggestion).update!(status: "accepted")
      end

      post accept_all_investment_suggestions_path
      expect(response).to redirect_to(investments_suggestions_path)
      expect(pending_1.reload.status).to eq("accepted")
      expect(pending_2.reload.status).to eq("accepted")
      expect(already_rejected.reload.status).to eq("rejected")
    end
  end

  describe "POST /investment_suggestions/:id/accept" do
    it "still requires an :id (member action)" do
      sugg = make_suggestion
      allow_any_instance_of(InvestmentSuggestionAcceptorService).to receive(:call) do |svc|
        svc.instance_variable_get(:@suggestion).update!(status: "accepted")
      end

      post accept_investment_suggestion_path(sugg)
      expect(response).to redirect_to(investments_suggestions_path)
      expect(sugg.reload.status).to eq("accepted")
    end
  end
end
