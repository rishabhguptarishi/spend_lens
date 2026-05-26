# frozen_string_literal: true

class NetWorthController < ApplicationController
  before_action :authenticate_user!

  def index
    data = NetWorthService.new(current_user).call
    holdings = current_user.investment_holdings.includes(:investment_account)

    render inertia: 'NetWorth/Index',
           props: data.merge(
             holdings: holdings.map { |h|
               {
                 id: h.id,
                 name: h.name,
                 asset_class: h.asset_class,
                 invested_amount: h.invested_amount.to_f,
                 account: h.investment_account.name,
               }
             },
             asset_class_labels: asset_class_labels
           )
  end

  private

  def asset_class_labels
    InvestmentHolding::ASSET_CLASSES.index_with { |c| c.humanize }
  end
end
