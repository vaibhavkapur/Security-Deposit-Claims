class RemoveExtractionMetadataFromDocuments < ActiveRecord::Migration[7.1]
  def change
    remove_column :documents, :extracted_at, :timestamptz
    remove_column :documents, :extractor_version, :text
  end
end
