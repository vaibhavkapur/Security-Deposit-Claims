class Document < ApplicationRecord
  STORAGE_ROOT = Rails.root.join("storage", "documents")

  belongs_to :claim

  validates :original_name, :relative_path, :byte_size, :storage_key, presence: true
  validates :content_hash, presence: true, uniqueness: true

  def storage_path
    STORAGE_ROOT.join(storage_key)
  end
end
