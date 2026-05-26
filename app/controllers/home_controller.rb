# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    if user_signed_in?
      redirect_to dashboard_path
    else
      render inertia: 'Home/Index'
    end
  end
end
