# frozen_string_literal: true

class InvestmentTransactionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transaction, only: [:edit, :update, :destroy]

  def new
    render inertia: 'Investments/Transactions/New',
           props: form_props
  end

  def create
    @inv_tx = current_user.investment_transactions.build(transaction_params.merge(source: 'manual'))
    if @inv_tx.save
      redirect_to investments_activity_path(fy: @inv_tx.financial_year_start), notice: 'Activity recorded.'
    else
      render inertia: 'Investments/Transactions/New',
             props: form_props.merge(errors: @inv_tx.errors.to_hash)
    end
  end

  def edit
    render inertia: 'Investments/Transactions/Edit',
           props: form_props.merge(transaction: investment_transaction_json(@inv_tx))
  end

  def update
    if @inv_tx.update(transaction_params)
      redirect_to investments_activity_path(fy: @inv_tx.financial_year_start), notice: 'Activity updated.'
    else
      render inertia: 'Investments/Transactions/Edit',
             props: form_props.merge(transaction: investment_transaction_json(@inv_tx), errors: @inv_tx.errors.to_hash)
    end
  end

  def destroy
    fy = @inv_tx.financial_year_start
    @inv_tx.destroy
    redirect_to investments_activity_path(fy: fy), notice: 'Activity deleted.'
  end

  private

  def set_transaction
    @inv_tx = current_user.investment_transactions.find(params[:id])
  end

  def form_props
    {
      accounts: current_user.investment_accounts.order(:name),
      holdings: current_user.investment_holdings.includes(:investment_account).order(:name),
      kinds: InvestmentTransaction::KINDS,
      asset_classes: InvestmentHolding::ASSET_CLASSES,
      financial_year_start: financial_year_param,
    }
  end

  def financial_year_param
    (params[:fy] || FinancialYear.current_start_year).to_i
  end

  def transaction_params
    params.require(:investment_transaction).permit(
      :investment_account_id, :investment_holding_id, :date, :kind, :amount,
      :units, :description, :asset_class, :financial_year_start
    )
  end

  def investment_transaction_json(t)
    t.as_json(only: %i[id date kind amount units description asset_class financial_year_start investment_account_id investment_holding_id])
  end
end
