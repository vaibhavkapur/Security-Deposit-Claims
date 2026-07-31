class Document < ApplicationRecord
  STORAGE_ROOT = Rails.root.join("storage", "documents")

  belongs_to :claim

  validates :original_name, :relative_path, :byte_size, :storage_key, presence: true
  validates :content_hash, presence: true, uniqueness: true

  scope :pending_extraction, -> {
    where(doc_type: DocumentExtraction::EXTRACTABLE_DOC_TYPES, extracted_json: nil)
  }

  def storage_path
    STORAGE_ROOT.join(storage_key)
  end

  def extractable?
    DocumentExtraction::EXTRACTABLE_DOC_TYPES.include?(doc_type)
  end

  def extracted?
    extracted_json.present?
  end

  def extraction_status
    return "extracted" if extracted?
    extractable? ? "pending" : "not_extractable"
  end
end
