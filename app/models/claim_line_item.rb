class ClaimLineItem < ApplicationRecord
  belongs_to :claim
  belongs_to :document

  DISPOSITIONS = %w[pending allowed disallowed needs_review].freeze

  validates :category, :description, :amount, presence: true
  validates :disposition, inclusion: {in: DISPOSITIONS}
end
