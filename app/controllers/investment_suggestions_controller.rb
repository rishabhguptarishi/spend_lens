# frozen_string_literal: true

class InvestmentSuggestionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_suggestion, only: %i[accept reject]

  def accept
    InvestmentSuggestionAcceptorService.new(current_user, @suggestion).call
    redirect_to investments_suggestions_path, notice: 'Added to portfolio.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to investments_suggestions_path, alert: e.record.errors.full_messages.join(', ')
  end

  def reject
    @suggestion.update!(status: 'rejected')
    redirect_to investments_suggestions_path, notice: 'Suggestion dismissed.'
  end

  # Phase 4 §5.7: when `ids` is given the user is bulk-accepting a SUBSET
  # (a single confidence-bucket from /investments/suggestions). When
  # absent the old "accept everything" behavior is preserved so direct
  # links / scripts keep working.
  def accept_all
    scope = current_user.investment_suggestions.pending.includes(:source_transaction)
    scope = scope.where(id: Array(params[:ids])) if params[:ids].present?

    count = 0
    scope.find_each do |s|
      InvestmentSuggestionAcceptorService.new(current_user, s).call
      count += 1
    rescue ActiveRecord::RecordInvalid
      next
    end
    redirect_to investments_suggestions_path, notice: "Accepted #{count} suggestion(s)."
  end

  private

  def set_suggestion
    @suggestion = current_user.investment_suggestions.find(params[:id])
  end
end
