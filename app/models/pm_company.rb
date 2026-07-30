class PmCompany < ApplicationRecord
  has_many :property_managers, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
