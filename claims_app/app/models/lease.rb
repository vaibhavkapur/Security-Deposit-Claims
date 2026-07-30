class Lease < ApplicationRecord
  belongs_to :property
  belongs_to :property_manager, optional: true
  has_many :tenants, dependent: :destroy
  has_many :claims, dependent: :destroy
end
