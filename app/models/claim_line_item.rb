class ClaimLineItem < ApplicationRecord
  belongs_to :claim
  belongs_to :document

  DISPOSITIONS = %w[allowed denied].freeze

  validates :category, :description, :amount, presence: true
  validates :disposition, inclusion: {in: DISPOSITIONS}
  validates :disposition_reason, presence: true
end
