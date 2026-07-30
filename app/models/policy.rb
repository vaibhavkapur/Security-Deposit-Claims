class Policy < ApplicationRecord
  has_many :claims, dependent: :nullify

  validates :policy_number, presence: true, uniqueness: true
end
