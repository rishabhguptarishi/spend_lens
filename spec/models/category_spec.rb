# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  let(:user) { make_user }

  describe "associations" do
    it "belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "has many transactions with dependent nullify" do
      assoc = described_class.reflect_on_association(:transactions)
      expect(assoc.macro).to eq(:has_many)
      expect(assoc.options[:dependent]).to eq(:nullify)
    end
  end

  it "is creatable" do
    expect(user.categories.create!(name: "Adhoc")).to be_persisted
  end
end
