# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::Registry, type: :service do
  describe ".for" do
    it "returns SPENDING_READ + SPENDING_WRITE by default" do
      tools = described_class.for(mode: "spending")
      expect(tools).to include(*described_class::SPENDING_READ)
      expect(tools).to include(*described_class::SPENDING_WRITE)
    end

    it "omits write tools when allow_writes is false" do
      tools = described_class.for(mode: "spending", allow_writes: false)
      expect(tools).to include(*described_class::SPENDING_READ)
      expect(tools & described_class::SPENDING_WRITE).to be_empty
    end

    it "returns ITR_READ for itr mode (regardless of allow_writes)" do
      expect(described_class.for(mode: "itr")).to eq(described_class::ITR_READ)
      expect(described_class.for(mode: "itr", allow_writes: true)).to eq(described_class::ITR_READ)
    end
  end

  describe ".declarations" do
    it "produces one declaration hash per tool class" do
      tools = described_class.for(mode: "spending", allow_writes: false)
      decls = described_class.declarations(tools)
      expect(decls.size).to eq(tools.size)
      expect(decls.first).to include(:name, :description, :parameters)
    end
  end

  describe ".find" do
    it "looks tools up by tool_name" do
      tools = described_class.for(mode: "spending")
      target = tools.first
      expect(described_class.find(tools, target.tool_name)).to eq(target)
    end

    it "returns nil for an unknown name" do
      tools = described_class.for(mode: "spending")
      expect(described_class.find(tools, "no_such_tool")).to be_nil
    end
  end

  describe "write-action classification" do
    it "marks Propose* tools as write actions and others as read-only" do
      writes = described_class::SPENDING_WRITE
      reads  = described_class::SPENDING_READ
      expect(writes.map(&:write_action?)).to all(be true)
      expect(reads.map(&:write_action?)).to all(be false)
    end
  end
end
