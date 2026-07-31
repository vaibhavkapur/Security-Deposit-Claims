class Claim < ApplicationRecord
  belongs_to :lease
  belongs_to :policy, optional: true
  has_one :collection_record, dependent: :destroy
  has_many :claim_activities, dependent: :destroy
  # line items reference documents, so they must be destroyed first
  has_many :claim_line_items, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_one :adjudication_decision, dependent: :destroy

  validates :tracking_number, presence: true, uniqueness: true
end
