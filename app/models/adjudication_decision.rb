class AdjudicationDecision < ApplicationRecord
  belongs_to :claim

  OUTCOMES = %w[approve decline].freeze

  validates :outcome, inclusion: {in: OUTCOMES}
  validates :reason, presence: true
end
