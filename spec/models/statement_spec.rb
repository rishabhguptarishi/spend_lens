# frozen_string_literal: true

require "rails_helper"

RSpec.describe Statement, type: :model do
  let(:user) { make_user }
  let(:bank_account) { make_bank_account(user: user) }

  describe "associations" do
    it "belongs to a bank_account" do
      expect(described_class.reflect_on_association(:bank_account).macro).to eq(:belongs_to)
    end

    it "has many transactions with dependent destroy" do
      assoc = described_class.reflect_on_association(:transactions)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  describe "#overlaps?" do
    let(:bank) { make_bank_account(user: user) }
    let(:stmt) do
      bank.statements.create!(
        month: 4, year: 2026,
        period_start: Date.new(2026, 4, 1),
        period_end: Date.new(2026, 4, 30),
      )
    end

    it "is true for any range touching the period" do
      expect(stmt.overlaps?(Date.new(2026, 4, 15), Date.new(2026, 5, 15))).to be true
      expect(stmt.overlaps?(Date.new(2026, 3, 15), Date.new(2026, 4, 5))).to be true
      expect(stmt.overlaps?(Date.new(2026, 4, 1), Date.new(2026, 4, 30))).to be true
    end

    it "is false for ranges entirely before or after the period" do
      expect(stmt.overlaps?(Date.new(2026, 3, 1), Date.new(2026, 3, 31))).to be false
      expect(stmt.overlaps?(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to be false
    end

    it "is false when either side has nil bounds" do
      bare = bank.statements.create!(month: 4, year: 2026)
      expect(bare.overlaps?(Date.new(2026, 4, 1), Date.new(2026, 4, 30))).to be false
      expect(stmt.overlaps?(nil, nil)).to be false
    end
  end

  describe "#period_label" do
    let(:bank) { make_bank_account(user: user) }

    it "renders a full-month label when the range matches a calendar month" do
      stmt = bank.statements.create!(
        month: 4, year: 2026,
        period_start: Date.new(2026, 4, 1),
        period_end: Date.new(2026, 4, 30),
      )
      expect(stmt.period_label).to eq("Apr 2026")
    end

    it "renders a range label for arbitrary periods" do
      stmt = bank.statements.create!(
        month: 4, year: 2026,
        period_start: Date.new(2026, 4, 5),
        period_end: Date.new(2027, 3, 31),
      )
      expect(stmt.period_label).to match(/05 Apr 2026.*31 Mar 2027/)
    end

    it "falls back to month/year when period is missing" do
      stmt = bank.statements.create!(month: 4, year: 2026)
      expect(stmt.period_label).to eq("4/2026")
    end
  end

  describe "file_content_type_and_size custom validation" do
    let(:statement) { make_statement(bank_account: bank_account) }

    it "accepts PDF files" do
      statement.file.attach(io: StringIO.new("dummy"), filename: "x.pdf", content_type: "application/pdf")
      expect(statement).to be_valid
    end

    it "accepts CSV files" do
      statement.file.attach(io: StringIO.new("a,b"), filename: "x.csv", content_type: "text/csv")
      expect(statement).to be_valid
    end

    it "rejects unsupported content types" do
      statement.file.attach(io: StringIO.new("<x/>"), filename: "x.xml", content_type: "application/xml")
      statement.valid?
      expect(statement.errors[:file].join).to match(/PDF or CSV/i)
    end

    it "rejects files larger than 25 MB" do
      big_blob = StringIO.new("x" * (26 * 1024 * 1024))
      statement.file.attach(io: big_blob, filename: "big.pdf", content_type: "application/pdf")
      statement.valid?
      expect(statement.errors[:file].join).to match(/too large|25/i)
    end
  end
end
