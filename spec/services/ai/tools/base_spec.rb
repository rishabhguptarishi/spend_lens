# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::Base, type: :service do
  let(:user) { make_user }

  describe ".tool_name" do
    it "derives the snake-case form of the demodulized class name" do
      stub_const("Ai::Tools::SampleThing", Class.new(described_class))
      expect(Ai::Tools::SampleThing.tool_name).to eq("sample_thing")
    end
  end

  describe ".description" do
    it "raises NotImplementedError by default" do
      expect { described_class.description }.to raise_error(NotImplementedError)
    end
  end

  describe ".declaration" do
    it "bundles name, description and parameters into a hash" do
      sub = Class.new(described_class) do
        def self.description; "test"; end
        def self.parameters_schema; { type: "object" }; end
      end
      stub_const("Ai::Tools::SampleDeclaration", sub)
      decl = Ai::Tools::SampleDeclaration.declaration
      expect(decl).to include(name: "sample_declaration", description: "test", parameters: { type: "object" })
    end
  end

  describe ".write_action?" do
    it "defaults to false" do
      expect(described_class.write_action?).to eq(false)
    end
  end

  describe "#call (abstract)" do
    it "raises NotImplementedError" do
      sub = Class.new(described_class) do
        def self.description; "test"; end
      end
      expect { sub.new(user).call({}) }.to raise_error(NotImplementedError)
    end
  end
end
