# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatementParsing::Persister, type: :service do
  let(:user) { make_user }
  let(:bank_account) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank_account, status: "uploaded") }

  let(:persister) { described_class.new(statement, user: user, bank_account: bank_account) }

  let(:rows) do
    [
      { date: Date.new(2026, 4, 10), description: "SWIGGY ORDER", amount: 350.0, transaction_type: "debit" },
      { date: Date.new(2026, 4, 15), description: "SALARY APRIL 2026", amount: 100_000.0, transaction_type: "credit" },
    ]
  end

  # Avoid hitting the live AI categorizer in every test. The dedicated test
  # below verifies the categorizer is called.
  before do
    allow_any_instance_of(TransactionCategorizationService).to receive(:categorize).and_return(nil)
    allow_any_instance_of(RecurringTransactionDetector).to receive(:recurring?).and_return(false)
  end

  it "creates Transaction rows on the given statement and returns the saved count" do
    count = persister.persist(rows)
    expect(count).to eq(2)
    expect(statement.transactions.count).to eq(2)
  end

  it "sets statement.status to 'parsed' on success" do
    persister.persist(rows)
    expect(statement.reload.status).to eq("parsed")
  end

  it "sets statement.status to 'failed' when nothing is saved" do
    persister.persist([])
    expect(statement.reload.status).to eq("failed")
  end

  it "dedupes against existing transactions on the same bank_account" do
    persister.persist(rows)

    # second statement, same bank account → all rows are duplicates
    second_statement = make_statement(bank_account: bank_account, month: 5, year: 2026, status: "uploaded")
    second_persister = described_class.new(second_statement, user: user, bank_account: bank_account)
    count = second_persister.persist(rows)
    expect(count).to eq(0)
  end

  it "does NOT dedupe against transactions on a different bank account" do
    persister.persist(rows)

    other_bank = make_bank_account(user: user, last_four: "9999")
    other_statement = make_statement(bank_account: other_bank, status: "uploaded")
    other_persister = described_class.new(other_statement, user: user, bank_account: other_bank)
    count = other_persister.persist(rows)
    expect(count).to eq(2)
  end

  it "categorizes via TransactionCategorizationService" do
    food = user.categories.find_by(name: "Food & Dining")
    # Override the default stub for this test only — re-stub before the persist
    # call so that this expectation wins over the default `before` hook.
    allow_any_instance_of(TransactionCategorizationService).to receive(:categorize).and_return(food)

    persister.persist([rows.first])
    expect(statement.transactions.first.category).to eq(food)
  end
end
