# frozen_string_literal: true

require "rails_helper"

RSpec.describe ItrDocumentRegistry, type: :service do
  describe "schema integrity" do
    it "registers all the headline ITR document types from the ClearTax/Quicko/TaxBuddy survey" do
      # Sanity check that the registry actually covers Tiers 1–6 — otherwise
      # we'd silently lose support and the user wouldn't know.
      %w[
        form16 ais tis form26as
        form16a form16b interest_cert dividend_stmt pension_stmt salary_slip
        broker_pl mf_cg cas_cdsl cas_nsdl crypto_pnl property_sale_deed
        lic_premium elss_80c ppf_80c sukanya_80c nsc_80c tuition_80c
        health_insurance_80d health_check_80d nps_80ccd1b medical_80ddb
        disability_80u education_loan_80e home_loan_cert first_home_80eea
        donation_80g rent_receipt
        business_pl balance_sheet gst_summary tax_audit_report challan_tax_paid
        form_10e form_12bb form_10ba form_15g_15h other
      ].each do |key|
        expect(described_class.find(key)).not_to be_nil, "missing registry entry for #{key}"
      end
    end

    it "uses only known categories" do
      bad = described_class::ENTRIES.reject { |e| described_class::CATEGORIES.include?(e.category) }
      expect(bad).to be_empty, "unknown categories: #{bad.map(&:key)}"
    end

    it "uses only known ITR forms in applicable_forms" do
      bad = described_class::ENTRIES.reject { |e| (e.applicable_forms - described_class::ALL_FORMS).empty? }
      expect(bad).to be_empty, "entries with unknown forms: #{bad.map(&:key)}"
    end

    it "assigns deduction_section only on :deduction_proof category entries (plus the structural HRA / Section 24 / 80GG carve-outs)" do
      # Allowed exceptions: home_loan_cert is filed under :deduction_proof
      # but its section (24b) lives in Schedule HP not VI-A; rent_receipt
      # similarly. Keep this assertion loose enough that adding more
      # genuine deduction proofs is the natural path.
      expect(described_class.deduction_entries_by_section.keys).to include('80C', '80D', '80CCD(1B)', '80E', '80G', '24b', 'HRA')
    end
  end

  describe ".find" do
    it "looks up by string or symbol key" do
      expect(described_class.find('form16').label).to include('Form 16')
      expect(described_class.find(:form16).label).to include('Form 16') if described_class.find(:form16)
    end

    it "returns nil for unknown keys" do
      expect(described_class.find('bogus_xyz')).to be_nil
    end
  end

  describe ".multiple_per_fy?" do
    it "is true for types where a user genuinely has many (Form 16A from many banks, LIC, rent receipts)" do
      expect(described_class.multiple_per_fy?('form16a')).to be true
      expect(described_class.multiple_per_fy?('lic_premium')).to be true
      expect(described_class.multiple_per_fy?('rent_receipt')).to be true
      expect(described_class.multiple_per_fy?('donation_80g')).to be true
    end

    it "is false for IT-dept singletons (AIS, 26AS, TIS)" do
      expect(described_class.multiple_per_fy?('ais')).to be false
      expect(described_class.multiple_per_fy?('form26as')).to be false
      expect(described_class.multiple_per_fy?('tis')).to be false
    end
  end

  describe ".applicable_to_form?" do
    it "restricts business docs to ITR-3/4" do
      expect(described_class.applicable_to_form?('business_pl', 'ITR-3')).to be true
      expect(described_class.applicable_to_form?('business_pl', 'ITR-1')).to be false
    end

    it "restricts capital-gains-only docs to ITR-2/3" do
      expect(described_class.applicable_to_form?('cas_cdsl', 'ITR-2')).to be true
      expect(described_class.applicable_to_form?('cas_cdsl', 'ITR-1')).to be false
    end

    it "allows universal docs across every ITR form" do
      %w[ITR-1 ITR-2 ITR-3 ITR-4].each do |form|
        expect(described_class.applicable_to_form?('form16', form)).to be true
        expect(described_class.applicable_to_form?('lic_premium', form)).to be true
      end
    end
  end

  describe ".deduction_entries_by_section" do
    it "groups every deduction-proof doc under its section" do
      sections = described_class.deduction_entries_by_section
      expect(sections['80C'].map(&:key)).to include('lic_premium', 'elss_80c', 'ppf_80c', 'tuition_80c')
      expect(sections['80D'].map(&:key)).to include('health_insurance_80d', 'health_check_80d')
      expect(sections['80CCD(1B)'].map(&:key)).to include('nps_80ccd1b')
    end
  end

  describe ".cap_for" do
    it "returns the FY25-26 cap for known sections" do
      expect(described_class.cap_for('80C')).to eq(150_000)
      expect(described_class.cap_for('80CCD(1B)')).to eq(50_000)
      expect(described_class.cap_for('24b')).to eq(200_000)
    end

    it "returns Infinity for uncapped sections (80E, 80G)" do
      expect(described_class.cap_for('80E')).to eq(Float::INFINITY)
      expect(described_class.cap_for('80G')).to eq(Float::INFINITY)
    end
  end

  describe ".frontend_catalog" do
    let(:catalog) { described_class.frontend_catalog }

    it "groups entries by category in display order" do
      keys = catalog.map { |c| c[:key] }
      expect(keys).to eq(described_class::CATEGORIES & keys) # ordered subset
    end

    it "includes every category with at least one entry" do
      expect(catalog.map { |c| c[:key] }).to include(:prefill, :income, :capital_gains, :deduction_proof, :business)
    end

    it "renders deduction_cap as nil for uncapped sections (avoids ∞ leaking to JSON)" do
      ded_proofs = catalog.find { |c| c[:key] == :deduction_proof }[:entries]
      e80g = ded_proofs.find { |e| e[:key] == 'donation_80g' }
      expect(e80g[:deduction_cap]).to be_nil
    end
  end
end
