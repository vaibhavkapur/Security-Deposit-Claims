class ClaimActivity < ApplicationRecord
  belongs_to :claim, optional: true

  validates :author, :body, :occurred_at, presence: true

  scope :unlinked, -> { where(claim_id: nil) }
  scope :chronological, -> { order(:occurred_at) }
end
