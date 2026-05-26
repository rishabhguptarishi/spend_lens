# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringTransactionDetector, type: :service do
  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }
  let(:statement) { make_statement(bank_account: bank, month: 4, year: 2026) }
  let(:detector) { described_class.new(user) }

  describe "#recurring?" do
    it "is true when the description contains a known recurring keyword" do
      expect(detector.recurring?("NETFLIX SUBSCRIPTION", 499, Date.new(2026, 4, 10))).to be true
      expect(detector.recurring?("Amazon Prime Renewal", 1499, Date.new(2026, 4, 10))).to be true
    end

    it "is false for a blank description" do
      expect(detector.recurring?(nil, 100, Date.today)).to be false
      expect(detector.recurring?("", 100, Date.today)).to be false
    end

    it "is false when no similar transactions exist in the prior 4 months" do
      expect(detector.recurring?("UPI-RANDOM MERCHANT", 250, Date.new(2026, 4, 10))).to be false
    end

    # All the heuristic tests below use a neutral merchant name ("FITPRO STUDIO")
    # that does NOT contain any of RECURRING_KEYWORDS, so they exercise the
    # actual SQL date-window logic rather than the keyword early-return.

    it "is true when ≥2 similar-amount, same-merchant transactions exist in the prior 4 months" do
      make_transaction(statement: statement, date: Date.new(2026, 1, 10), description: "FITPRO STUDIO",
                       amount: 1000, transaction_type: "debit")
      make_transaction(statement: statement, date: Date.new(2026, 2, 10), description: "FITPRO STUDIO",
                       amount: 1010, transaction_type: "debit") # within 5% tolerance

      expect(detector.recurring?("FITPRO STUDIO", 1000, Date.new(2026, 4, 10))).to be true
    end

    describe "regression: window must be anchored to the transaction's date (not Time.current)" do
      it "still detects recurring activity when the statement is in the past" do
        # Pre-fix, `4.months.ago` was anchored to Time.current. If the
        # statement is from May 2025 but the clock is May 2026, the lower
        # bound (Jan 2026) is after the upper bound (May 2025), so the
        # window collapses and the query always returns 0.
        make_transaction(statement: statement, date: Date.new(2025, 3, 10), description: "FITPRO STUDIO",
                         amount: 1000, transaction_type: "debit")
        make_transaction(statement: statement, date: Date.new(2025, 4, 10), description: "FITPRO STUDIO",
                         amount: 1000, transaction_type: "debit")

        expect(detector.recurring?("FITPRO STUDIO", 1000, Date.new(2025, 5, 10))).to be true
      end
    end

    it "ignores transactions outside the 4-month window" do
      make_transaction(statement: statement, date: Date.new(2025, 9, 10), description: "FITPRO STUDIO",
                       amount: 1000, transaction_type: "debit") # >4 months before
      make_transaction(statement: statement, date: Date.new(2025, 10, 10), description: "FITPRO STUDIO",
                       amount: 1000, transaction_type: "debit") # >4 months before
      expect(detector.recurring?("FITPRO STUDIO", 1000, Date.new(2026, 4, 10))).to be false
    end

    it "ignores transactions whose amount differs by >5%" do
      make_transaction(statement: statement, date: Date.new(2026, 2, 10), description: "FITPRO STUDIO",
                       amount: 1500, transaction_type: "debit")
      make_transaction(statement: statement, date: Date.new(2026, 3, 10), description: "FITPRO STUDIO",
                       amount: 1500, transaction_type: "debit")
      expect(detector.recurring?("FITPRO STUDIO", 1000, Date.new(2026, 4, 10))).to be false
    end

    it "scopes by user" do
      other_user = make_user
      other_bank = make_bank_account(user: other_user)
      other_stmt = make_statement(bank_account: other_bank)
      make_transaction(statement: other_stmt, date: Date.new(2026, 2, 10), description: "FITPRO STUDIO",
                       amount: 1000, transaction_type: "debit")
      make_transaction(statement: other_stmt, date: Date.new(2026, 3, 10), description: "FITPRO STUDIO",
                       amount: 1000, transaction_type: "debit")
      expect(detector.recurring?("FITPRO STUDIO", 1000, Date.new(2026, 4, 10))).to be false
    end
  end
end
