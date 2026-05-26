# frozen_string_literal: true

class ItrReconciliationController < ApplicationController
  before_action :authenticate_user!

  def show
    fy = financial_year_param
    snapshot = ItrFySnapshot.new(current_user, financial_year_start: fy)
    data = snapshot.reconciliation

    render inertia: 'Itr/Reconciliation',
           props: data.merge(years: FinancialYear.available_years, year: fy)
  end

  private

  def financial_year_param
    year = (params[:year] || FinancialYear.current_start_year).to_i
    FinancialYear.available_years.include?(year) ? year : FinancialYear.current_start_year
  end
end
