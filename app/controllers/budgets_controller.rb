# frozen_string_literal: true

class BudgetsController < ApplicationController
  before_action :authenticate_user!

  def index
    now = Date.current
    month_budgets = current_user.budgets.for_period(now.month, now.year).to_a
    general_budgets = current_user.budgets.general.to_a

    budget_data = current_user.categories.map do |cat|
      budget = month_budgets.find { |b| b.category_id == cat.id } || general_budgets.find { |b| b.category_id == cat.id }
      spent = spent_for_category(cat, now)
      amount = budget&.amount&.to_f || 0
      {
        category: cat.as_json,
        budget: budget&.as_json,
        amount: amount,
        spent: spent,
        remaining: amount - spent,
      }
    end
    budget_data = budget_data.select { |b| b[:amount].positive? || b[:spent].positive? }

    render inertia: 'Budgets/Index',
           props: {
             budgets: budget_data,
             categories: current_user.categories,
             month: now.month,
             year: now.year,
           }
  end

  def create
    budget = current_user.budgets.find_or_initialize_by(
      category_id: budget_params[:category_id],
      month: params[:month].presence&.to_i,
      year: params[:year].presence&.to_i
    )
    budget.amount = budget_params[:amount]
    budget.month = params[:month].presence&.to_i
    budget.year = params[:year].presence&.to_i
    if budget.save
      redirect_to budgets_path, notice: 'Budget updated.'
    else
      redirect_to budgets_path, alert: budget.errors.full_messages.join(', ')
    end
  end

  def update
    budget = current_user.budgets.find(params[:id])
    if budget.update(budget_params)
      redirect_to budgets_path, notice: 'Budget updated.'
    else
      redirect_to budgets_path, alert: budget.errors.full_messages.join(', ')
    end
  end

  def destroy
    current_user.budgets.find(params[:id]).destroy
    redirect_to budgets_path, notice: 'Budget removed.'
  end

  private

  def spent_for_category(category, now)
    Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .where(transaction_type: 'debit', category_id: category.id)
      .where("EXTRACT(MONTH FROM transactions.date) = ?", now.month)
      .where("EXTRACT(YEAR FROM transactions.date) = ?", now.year)
      .sum(:amount)
      .to_f
  end

  def budget_params
    params.require(:budget).permit(:category_id, :amount)
  end
end
