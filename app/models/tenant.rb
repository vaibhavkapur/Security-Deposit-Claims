class Tenant < ApplicationRecord
  belongs_to :lease

  validates :tenant_number, presence: true,
                            numericality: { only_integer: true, in: 1..3 },
                            uniqueness: { scope: :lease_id }
end
