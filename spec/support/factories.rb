# frozen_string_literal: true

# Lightweight factory helpers. (We aren't pulling in factory_bot since it's
# not in the Gemfile yet — these methods keep specs concise without that
# dependency.)
module SpecFactories
  module_function

  def make_user(email: nil, password: "password123")
    User.create!(email: email || "user-#{SecureRandom.hex(4)}@example.com", password: password)
  end

  def make_bank_account(user:, **overrides)
    user.bank_accounts.create!({
      name: "HDFC •••• 1234",
      bank_name: "HDFC",
      account_type: "savings",
      last_four: "1234",
    }.merge(overrides))
  end

  def make_statement(bank_account:, month: 4, year: 2026, status: "processed")
    bank_account.statements.create!(month: month, year: year, status: status)
  end

  def make_transaction(statement:, **overrides)
    statement.transactions.create!({
      date: Date.new(2026, 4, 10),
      description: "TEST TXN",
      amount: 100.0,
      transaction_type: "debit",
    }.merge(overrides))
  end

  def make_investment_account(user:, **overrides)
    user.investment_accounts.create!({
      name: "Zerodha",
      account_kind: "broker",
    }.merge(overrides))
  end

  def make_investment_holding(user:, investment_account: nil, **overrides)
    user.investment_holdings.create!({
      investment_account: investment_account || make_investment_account(user: user),
      name: "INFY",
      asset_class: "stock",
    }.merge(overrides))
  end

  def make_investment_transaction(user:, **overrides)
    user.investment_transactions.create!({
      date: Date.new(2026, 4, 10),
      kind: "buy",
      amount: 10_000.0,
      source: "manual",
    }.merge(overrides))
  end
end

RSpec.configure do |config|
  config.include SpecFactories
end
