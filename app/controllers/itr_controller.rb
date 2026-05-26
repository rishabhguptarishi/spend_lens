# frozen_string_literal: true

class ItrController < ApplicationController
  before_action :authenticate_user!

  def index
    fy = financial_year_param
    range = FinancialYear.range_for(fy)
    snapshot = ItrFySnapshot.new(current_user, financial_year_start: fy)
    readiness = snapshot.readiness
    savings = snapshot.tax_savings

    transactions = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .where(date: range)

    income = transactions.where(transaction_type: 'credit').sum(:amount)
    expenses = transactions.where(transaction_type: 'debit').sum(:amount)

    by_category = transactions
      .where(transaction_type: 'debit')
      .joins('LEFT JOIN categories ON categories.id = transactions.category_id')
      .group('COALESCE(categories.name, \'Uncategorized\')')
      .sum(:amount)

    by_month = transactions
      .where(transaction_type: 'debit')
      .group("DATE_TRUNC('month', transactions.date)")
      .sum(:amount)
      .transform_keys { |k| k.is_a?(Time) ? k.strftime('%b %Y') : k.to_s }

    render inertia: 'Itr/Index',
           props: {
             year: fy,
             years: FinancialYear.available_years,
             financial_year_label: FinancialYear.label(fy),
             income: income.to_f,
             expenses: expenses.to_f,
             by_category: by_category,
             by_month: by_month,
             readiness: readiness,
             tax_savings: savings,
             # Full registry catalog — frontend renders sections from this
             # rather than hard-coding which doc types exist. Filtered to
             # the docs that apply to the currently-suggested ITR form.
             document_catalog: filtered_catalog(readiness),
           }
  end

  def regime
    fy = financial_year_param
    snapshot = ItrFySnapshot.new(current_user, financial_year_start: fy)
    regime = snapshot.regime_compare(deductions: regime_params)

    render inertia: 'Itr/Regime',
           props: {
             year: fy,
             years: FinancialYear.available_years,
             regime: regime,
           }
  end

  def capital_gains
    fy = financial_year_param
    summary = CapitalGainsSummaryService.new(current_user, financial_year_start: fy).call

    render inertia: 'Itr/CapitalGains',
           props: summary.merge(year: fy, years: FinancialYear.available_years)
  end

  def capital_gains_export
    fy = financial_year_param
    csv = CapitalGainsSummaryService.new(current_user, financial_year_start: fy).to_csv
    send_data csv, filename: "capital_gains_#{fy}.csv", type: 'text/csv'
  end

  def tax_pack
    fy = financial_year_param
    zip = TaxPackBuilderService.new(current_user, financial_year_start: fy).call
    send_data zip,
              filename: "spendlens_tax_pack_FY#{fy}.zip",
              type: 'application/zip'
  end

  def export
    fy = financial_year_param
    format = params[:format] || 'csv'
    range = FinancialYear.range_for(fy)

    transactions = Transaction
      .joins(statement: :bank_account)
      .includes(:category, statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .where(date: range)
      .order(:date)

    case format
    when 'csv'
      send_data itr_csv(transactions, fy), filename: "itr_summary_#{fy}.csv", type: 'text/csv'
    when 'xlsx'
      send_data itr_xlsx(transactions, fy),
                filename: "itr_summary_#{fy}.xlsx",
                type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'pdf'
      send_data itr_pdf(transactions, fy),
                filename: "itr_summary_#{fy}.pdf",
                type: 'application/pdf',
                disposition: 'inline'
    else
      redirect_to itr_path(year: fy), alert: 'Unsupported format.'
    end
  end

  private

  # Returns the registry catalog filtered to entries that apply to the
  # user's suggested ITR form, with uploaded counts wired in. The catalog
  # itself stays generic — applicability is the only filter we apply.
  def filtered_catalog(readiness)
    form = readiness.dig(:suggested_itr_form, :form) || 'ITR-1'
    inventory = readiness[:documents] || {}

    ItrDocumentRegistry.frontend_catalog.filter_map do |category|
      entries = category[:entries].select { |e| e[:applicable_forms].include?(form) }
      next if entries.empty?

      enriched_entries = entries.map do |entry|
        inv = inventory[entry[:key]] || {}
        entry.merge(
          count: inv[:count].to_i,
          uploaded: inv[:uploaded] == true,
          instances: inv[:instances] || []
        )
      end

      category.merge(entries: enriched_entries)
    end
  end

  def financial_year_param
    year = (params[:year] || FinancialYear.current_start_year).to_i
    available = FinancialYear.available_years
    available.include?(year) ? year : FinancialYear.current_start_year
  end

  def regime_params
    params
      .permit(:deduction_80c, :deduction_80d, :hra)
      .to_h
      .transform_values { |v| v.to_s.strip.presence&.to_f }
      .compact
      .symbolize_keys
  end

  def itr_csv(transactions, fy)
    require 'csv'
    label = FinancialYear.label(fy)
    CSV.generate do |csv|
      csv << ['ITR Summary', "FY #{label} (Apr-Mar)"]
      csv << []
      csv << ['Date', 'Description', 'Type', 'Amount', 'Category', 'Bank Account']
      transactions.each do |t|
        csv << [
          t.date,
          t.description,
          t.transaction_type,
          t.amount,
          t.category&.name || 'Uncategorized',
          t.statement.bank_account.name,
        ]
      end
      csv << []
      income = transactions.where(transaction_type: 'credit').sum(:amount)
      expenses = transactions.where(transaction_type: 'debit').sum(:amount)
      csv << ['Total Income', income]
      csv << ['Total Expenses', expenses]
      csv << ['Net', income - expenses]
    end
  end

  def itr_xlsx(transactions, fy)
    require 'caxlsx'
    label = FinancialYear.label(fy)
    p = Axlsx::Package.new
    wb = p.workbook
    wb.add_worksheet(name: 'ITR Summary') do |sheet|
      sheet.add_row ['ITR Summary', "FY #{label} (Apr-Mar)"]
      sheet.add_row []
      sheet.add_row ['Date', 'Description', 'Type', 'Amount', 'Category', 'Bank Account']
      transactions.each do |t|
        sheet.add_row [t.date, t.description, t.transaction_type, t.amount, t.category&.name || 'Uncategorized', t.statement.bank_account.name]
      end
      sheet.add_row []
      income = transactions.where(transaction_type: 'credit').sum(:amount)
      expenses = transactions.where(transaction_type: 'debit').sum(:amount)
      sheet.add_row ['Total Income', income]
      sheet.add_row ['Total Expenses', expenses]
      sheet.add_row ['Net', income - expenses]
    end
    p.to_stream.read
  end

  def itr_pdf(transactions, fy)
    require 'prawn'
    require 'prawn/table'
    label = FinancialYear.label(fy)
    income = transactions.where(transaction_type: 'credit').sum(:amount)
    expenses = transactions.where(transaction_type: 'debit').sum(:amount)
    pdf = Prawn::Document.new
    pdf.text "ITR Summary - FY #{label} (Apr-Mar)", size: 18, style: :bold
    pdf.move_down 20
    pdf.text "Income: ₹#{income.to_f.round(2)}"
    pdf.text "Expenses: ₹#{expenses.to_f.round(2)}"
    pdf.text "Net: ₹#{(income - expenses).to_f.round(2)}", style: :bold
    pdf.move_down 20
    data = [['Date', 'Description', 'Type', 'Amount', 'Category']]
    transactions.limit(100).each do |t|
      data << [t.date.to_s, t.description.to_s[0..40], t.transaction_type, t.amount, t.category&.name || '-']
    end
    pdf.table(data, header: true, row_colors: %w[ffffff f8f8f8])
    pdf.render
  end
end
