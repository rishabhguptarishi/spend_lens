# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Investments::SourcePriority do
  it 'ranks depository CAS highest (100)' do
    expect(described_class.for('cdsl_cas')).to eq(100)
    expect(described_class.for('nsdl_cas')).to eq(100)
  end

  it 'ranks registrar CAS at 95' do
    expect(described_class.for('mf_cas')).to eq(95)
    expect(described_class.for('cams_cas')).to eq(95)
    expect(described_class.for('kfintech_cas')).to eq(95)
  end

  it 'ranks tax-grade docs at 90' do
    expect(described_class.for('tax_doc')).to eq(90)
    expect(described_class.for('broker_pl')).to eq(90)
    expect(described_class.for('mf_cg')).to eq(90)
  end

  it 'ranks broker CSV imports at 80' do
    expect(described_class.for('broker_import')).to eq(80)
  end

  it 'ranks bank statement passbook (FD/RD/PPF block) at 75' do
    expect(described_class.for('bank_statement')).to eq(75)
  end

  it 'ranks bank-detected suggestions at 60' do
    expect(described_class.for('bank_detect')).to eq(60)
  end

  it 'ranks manual entries lowest (40)' do
    expect(described_class.for('manual')).to eq(40)
  end

  it 'returns a sane DEFAULT for unknown sources' do
    expect(described_class.for('totally_unknown')).to eq(50)
  end
end
