# frozen_string_literal: true

class CategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_category, only: [:edit, :update, :destroy]

  def index
    # One grouped COUNT instead of N per-category .count queries. Bullet was
    # flagging this as both an N+1 (the loop) and a counter-cache opportunity;
    # this collapses it to a single round-trip without adding a denormalized
    # column.
    counts = Transaction
      .joins(statement: :bank_account)
      .where(bank_accounts: { user_id: current_user.id })
      .where.not(category_id: nil)
      .group(:category_id)
      .count

    categories = current_user.categories.map do |c|
      c.attributes.merge('transactions_count' => counts[c.id] || 0)
    end

    render inertia: 'Categories/Index',
           props: {
             categories: categories,
           }
  end

  def new
    used_colors = current_user.categories.pluck(:color).compact.map { |c| c.to_s.downcase.strip }.uniq
    render inertia: 'Categories/New',
           props: { used_colors: used_colors }
  end

  def create
    @category = current_user.categories.build(category_params)
    @category.color = ensure_unique_color(@category.color, exclude_category_id: nil) if @category.color.present?
    if @category.save
      redirect_to categories_path, notice: 'Category created.'
    else
      used_colors = current_user.categories.pluck(:color).compact.map { |c| c.to_s.downcase.strip }.uniq
      render inertia: 'Categories/New', props: { errors: @category.errors.to_hash, used_colors: used_colors }
    end
  end

  def edit
    used_colors = current_user.categories.where.not(id: @category.id).pluck(:color).compact.map { |c| c.to_s.downcase.strip }.uniq
    render inertia: 'Categories/Edit', props: { category: @category, used_colors: used_colors }
  end

  def update
    params = category_params
    params[:color] = ensure_unique_color(params[:color], exclude_category_id: @category.id) if params[:color].present?
    if @category.update(params)
      redirect_to categories_path, notice: 'Category updated.'
    else
      used_colors = current_user.categories.where.not(id: @category.id).pluck(:color).compact.map { |c| c.to_s.downcase.strip }.uniq
      render inertia: 'Categories/Edit', props: { category: @category, errors: @category.errors.to_hash, used_colors: used_colors }
    end
  end

  def destroy
    @category.destroy
    redirect_to categories_path, notice: 'Category deleted.'
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :color)
  end

  def ensure_unique_color(color, exclude_category_id: nil)
    return color if color.blank?

    scope = current_user.categories
    scope = scope.where.not(id: exclude_category_id) if exclude_category_id.present?
    used = scope.pluck(:color).compact.map { |c| c.to_s.downcase.strip }.uniq
    return color unless used.include?(color.to_s.downcase.strip)

    palette = %w[#F59E0B #3B82F6 #8B5CF6 #10B981 #EC4899 #EF4444 #06B6D4 #6B7280 #22c55e #84cc16 #f97316 #14b8a6 #a855f7 #e11d48 #0ea5e9 #64748b]
    available = palette.map(&:downcase) - used
    available.any? ? available.first : color
  end
end
