class AddExtractionToDocuments < ActiveRecord::Migration[7.1]
  def change
    change_table :documents, bulk: true do |t|
      t.text :extraction_status, null: false, default: "pending"
      # pending | extracted | failed | refused | not_extractable
      t.jsonb :extracted_json
      t.timestamptz :extracted_at
      t.text :extractor_version
      t.text :extraction_error
    end

    add_index :documents, :extraction_status
  end
end
