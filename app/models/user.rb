class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :timeoutable, :lockable

  has_many :bank_accounts, dependent: :destroy
  # Phase 6 §G14: read-only convenience association. Actual cascade
  # delete happens through bank_accounts → statements → transactions
  # (set up on those models). We deliberately omit `dependent:` here so
  # we don't issue two cascading deletes against the same rows.
  has_many :transactions
  has_many :credit_cards, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :category_rules, dependent: :destroy
  has_many :budgets, dependent: :destroy
  has_many :investment_accounts, dependent: :destroy
  has_many :investment_holdings, dependent: :destroy
  has_many :investment_transactions, dependent: :destroy
  has_many :investment_suggestions, dependent: :destroy
  has_many :investment_positions, dependent: :destroy
  has_many :itr_tax_documents, dependent: :destroy
  has_many :investment_import_batches, dependent: :destroy
  has_one :user_notification_preference, dependent: :destroy
  has_many :user_investment_detection_rules, dependent: :destroy

  after_create :ensure_default_categories
  after_create :ensure_notification_preferences

  def preferences
    self[:preferences].presence || {}
  end

  def user_preference
    UserPreference.new(self)
  end

  # Public so controllers can ensure categories exist before parsing
  def ensure_default_categories
    return if categories.exists?

    DEFAULT_CATEGORIES.each do |attrs|
      categories.create!(name: attrs[:name], color: attrs[:color])
    end
  end

  DEFAULT_CATEGORIES = [
    { name: 'Food & Dining', color: '#F59E0B' },
    { name: 'Transport', color: '#3B82F6' },
    { name: 'Shopping', color: '#8B5CF6' },
    { name: 'Utilities', color: '#10B981' },
    { name: 'Entertainment', color: '#EC4899' },
    { name: 'Healthcare', color: '#EF4444' },
    { name: 'Travel', color: '#06B6D4' },
    { name: 'Transfer', color: '#6B7280' },
    { name: 'Income', color: '#22c55e' }, # Green - distinct from Transfer (gray)
  ].freeze

  def ensure_notification_preferences
    create_user_notification_preference! unless user_notification_preference
  end

  private
end
