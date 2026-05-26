# frozen_string_literal: true

class InvestmentDetectionRulesController < ApplicationController
  before_action :authenticate_user!

  def create
    rule = current_user.user_investment_detection_rules.build(rule_params)
    if rule.save
      redirect_to settings_path, notice: 'Detection rule added.'
    else
      redirect_to settings_path, alert: rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    rule = current_user.user_investment_detection_rules.find(params[:id])
    rule.destroy!
    redirect_to settings_path, notice: 'Detection rule removed.'
  end

  private

  def rule_params
    params.require(:investment_detection_rule).permit(
      :pattern, :asset_class, :kind, :account_name, :account_kind, :position
    )
  end
end
