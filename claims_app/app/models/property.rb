class Property < ApplicationRecord
  has_many :leases, dependent: :destroy

  validates :street_address, presence: true

  def full_address
    [street_address, city, state, zip].compact.join(", ")
  end
end
