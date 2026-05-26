# frozen_string_literal: true

require "rails_helper"

RSpec.describe BankAccount, type: :model do
  let(:user) { make_user }

  describe "associations" do
    it "belongs to a user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "has many statements (dependent destroy)" do
      assoc = described_class.reflect_on_association(:statements)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:destroy)
    end
  end

  it "is creatable with the standard factory" do
    expect(make_bank_account(user: user)).to be_persisted
  end

  it "destroys statements when destroyed" do
    bank = make_bank_account(user: user)
    make_statement(bank_account: bank)
    expect { bank.destroy }.to change { Statement.count }.by(-1)
  end
end
