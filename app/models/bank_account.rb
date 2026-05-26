class BankAccount < ApplicationRecord
  belongs_to :user
  has_many :statements, dependent: :destroy
end
