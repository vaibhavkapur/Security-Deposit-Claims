class Claim < ApplicationRecord
  belongs_to :lease
  belongs_to :policy, optional: true
  has_one :collection_record, dependent: :destroy
  has_many :claim_activities, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :claim_line_items, dependent: :destroy
  has_many :adjudication_decisions, dependent: :destroy

  validates :tracking_number, presence: true, uniqueness: true
end
