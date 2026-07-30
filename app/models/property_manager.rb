class PropertyManager < ApplicationRecord
  belongs_to :pm_company
  has_many :leases, dependent: :nullify

  validates :name, presence: true
end
