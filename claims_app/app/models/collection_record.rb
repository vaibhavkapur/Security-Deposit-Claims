# Backed by the "collections" table; named CollectionRecord to avoid
# colliding with Ruby/Rails collection concepts.
class CollectionRecord < ApplicationRecord
  self.table_name = "collections"

  belongs_to :claim

  validates :claim_id, uniqueness: true
end
