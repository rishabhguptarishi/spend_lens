# frozen_string_literal: true

require 'zip'

class TaxPackBuilderService
  def initialize(user, financial_year_start:)
    @user = user
    @fy = financial_year_start.to_i
  end

  def call
    snapshot = ItrFySnapshot.new(@user, financial_year_start: @fy)
    readiness = snapshot.readiness
    reconciliation = snapshot.reconciliation
    regime = snapshot.regime_compare
    # snapshot.capital_gains returns the Hash result; instantiate the service
    # directly here so we can call #to_csv for the ZIP entry.
    capital_gains_csv = CapitalGainsSummaryService.new(@user, financial_year_start: @fy).to_csv

    buffer = Zip::OutputStream.write_buffer do |zio|
      zio.put_next_entry('README.txt')
      zio.write readme_text

      zio.put_next_entry('income_expense_summary.csv')
      zio.write income_expense_csv(readiness)

      zio.put_next_entry('investment_fy_summary.csv')
      zio.write investment_csv(readiness[:investment_summary])

      zio.put_next_entry('capital_gains.csv')
      zio.write capital_gains_csv

      zio.put_next_entry('ais_reconciliation.csv')
      zio.write reconciliation_csv(reconciliation)

      zio.put_next_entry('regime_comparison.csv')
      zio.write regime_csv(regime)

      zio.put_next_entry('filing_guide.txt')
      zio.write filing_guide(readiness)
    end

    buffer.string
  end

  private

  def readme_text
    <<~TXT
      SpendLens Tax Pack — FY #{FinancialYear.label(@fy)}
      Generated: #{Time.current}
      DISCLAIMER: Assistive only. Not a substitute for a Chartered Accountant.
      File at https://www.incometax.gov.in
    TXT
  end

  def income_expense_csv(readiness)
    require 'csv'
    CSV.generate do |csv|
      csv << %w[Metric Amount_INR]
      csv << ['Total income (bank)', readiness[:income]]
      csv << ['Salary estimate', readiness[:salary_estimate]]
      csv << ['Expenses', readiness[:expenses]]
      csv << ['Net', readiness[:net]]
      csv << ['Suggested form', readiness.dig(:suggested_itr_form, :form)]
    end
  end

  def investment_csv(inv)
    require 'csv'
    CSV.generate do |csv|
      csv << %w[Metric Amount_INR]
      csv << ['Contributions', inv[:contributions]]
      csv << ['Sells', inv[:sells]]
      csv << ['Dividends/interest', inv[:dividends_interest]]
      csv << ['Holdings count', inv[:holdings_count]]
    end
  end

  def reconciliation_csv(rec)
    require 'csv'
    CSV.generate do |csv|
      csv << %w[Line AIS SpendLens Difference Status Note]
      rec[:rows].each do |r|
        csv << [r[:label], r[:ais_amount], r[:spendlens_amount], r[:difference], r[:status], r[:note]]
      end
    end
  end

  def regime_csv(regime)
    require 'csv'
    CSV.generate do |csv|
      csv << ['Regime', 'Taxable', 'Tax', 'Cess', 'Total']
      csv << ['New', regime.dig(:new_regime, :taxable), regime.dig(:new_regime, :tax), regime.dig(:new_regime, :cess), regime.dig(:new_regime, :total)]
      csv << ['Old', regime.dig(:old_regime, :taxable), regime.dig(:old_regime, :tax), regime.dig(:old_regime, :cess), regime.dig(:old_regime, :total)]
      csv << ['Likely better', regime[:likely_better]]
    end
  end

  def filing_guide(readiness)
    form = readiness.dig(:suggested_itr_form, :form) || 'ITR-1'
    <<~TXT
      Personalized filing checklist — FY #{FinancialYear.label(@fy)}

      1. Log in to incometax.gov.in
      2. Select Assessment Year #{@fy + 1}-#{format('%02d', (@fy + 2) % 100)}
      3. Choose #{form} (#{readiness.dig(:suggested_itr_form, :reason)})
      4. Pre-fill salary from Form 16 or bank salary credits
      5. Schedule capital gains if broker/MF activity present
      6. Match TDS with Form 26AS
      7. Select tax regime (see regime_comparison.csv)
      8. Verify AIS reconciliation gaps
      9. Submit and e-verify

      Readiness: #{readiness[:readiness_pct]}%
    TXT
  end
end
