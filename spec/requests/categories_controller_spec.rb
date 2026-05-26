# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoriesController, type: :request do
  let(:user) { make_user }

  before { sign_in(user) }

  describe "GET /categories" do
    it "responds 200 and renders the Categories/Index page" do
      get categories_path, headers: { "X-Inertia" => "true" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["component"]).to eq("Categories/Index")
    end

    it "returns accurate transactions_count per category" do
      food = user.categories.find_by(name: "Food & Dining")
      bank = make_bank_account(user: user)
      stmt = make_statement(bank_account: bank, status: "parsed")
      3.times { make_transaction(statement: stmt, category: food) }

      get categories_path, headers: { "X-Inertia" => "true" }
      categories = JSON.parse(response.body).dig("props", "categories")
      food_row = categories.find { |c| c["id"] == food.id }
      expect(food_row["transactions_count"]).to eq(3)

      other = categories.reject { |c| c["id"] == food.id }
      expect(other.map { |c| c["transactions_count"] }).to all(eq(0))
    end

    it "regression: counts come from ONE grouped query, not N per-category counts" do
      user.categories.first(3).each do |cat|
        bank = make_bank_account(user: user, last_four: SecureRandom.hex(2))
        stmt = make_statement(bank_account: bank, status: "parsed")
        make_transaction(statement: stmt, category: cat)
      end

      count_queries = 0
      subscriber = ->(_name, _started, _finished, _id, payload) {
        sql = payload[:sql].to_s
        # Per-association count would look like SELECT COUNT(*) FROM transactions WHERE category_id = ?
        # The grouped version uses GROUP BY. We only count COUNT(*) queries
        # against the transactions table to assert there's exactly one.
        next unless sql.match?(/SELECT COUNT.*FROM\s+"transactions"/i)
        count_queries += 1
      }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get categories_path, headers: { "X-Inertia" => "true" }
      end

      expect(count_queries).to eq(1),
        "expected exactly one transactions COUNT query, got #{count_queries} (this would mean per-category .count is back)"
    end
  end
end
