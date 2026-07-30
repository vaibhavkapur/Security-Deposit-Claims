class AdjudicationDecision < ApplicationRecord
  belongs_to :claim

  STAGES = %w[eligibility amount final].freeze
  OUTCOMES = %w[approve decline refer hold].freeze

  validates :stage, inclusion: {in: STAGES}
  validates :outcome, inclusion: {in: OUTCOMES}
  validates :decided_by, :rule_or_reason, presence: true

  # Append-only: existing rows can never be updated or destroyed.
  def readonly? = persisted?
end
