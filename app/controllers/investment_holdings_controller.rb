# frozen_string_literal: true

class InvestmentHoldingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_holding, only: [:edit, :update, :destroy]

  def new
    accounts = current_user.investment_accounts.order(:name)
    render inertia: 'Investments/Holdings/New',
           props: {
             accounts: accounts,
             asset_classes: InvestmentHolding::ASSET_CLASSES,
           }
  end

  def create
    account = current_user.investment_accounts.find(holding_params[:investment_account_id])
    @holding = current_user.investment_holdings.build(holding_params.merge(investment_account: account))
    if @holding.save
      redirect_to investments_path, notice: 'Holding added.'
    else
      render inertia: 'Investments/Holdings/New',
             props: {
               accounts: current_user.investment_accounts.order(:name),
               asset_classes: InvestmentHolding::ASSET_CLASSES,
               errors: @holding.errors.to_hash,
             }
    end
  end

  def edit
    render inertia: 'Investments/Holdings/Edit',
           props: {
             holding: @holding,
             accounts: current_user.investment_accounts.order(:name),
             asset_classes: InvestmentHolding::ASSET_CLASSES,
           }
  end

  def update
    if @holding.update(holding_params)
      redirect_to investments_path, notice: 'Holding updated.'
    else
      render inertia: 'Investments/Holdings/Edit',
             props: {
               holding: @holding,
               accounts: current_user.investment_accounts.order(:name),
               asset_classes: InvestmentHolding::ASSET_CLASSES,
               errors: @holding.errors.to_hash,
             }
    end
  end

  def destroy
    @holding.destroy
    redirect_to investments_path, notice: 'Holding removed.'
  end

  private

  def set_holding
    @holding = current_user.investment_holdings.find(params[:id])
  end

  def holding_params
    params.require(:investment_holding).permit(
      :investment_account_id, :asset_class, :name, :symbol, :folio,
      :units, :avg_cost, :invested_amount
    )
  end
end
