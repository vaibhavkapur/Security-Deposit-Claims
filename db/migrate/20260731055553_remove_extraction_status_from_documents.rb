class RemoveExtractionStatusFromDocuments < ActiveRecord::Migration[7.1]
  def change
    remove_column :documents, :extraction_status, :text, default: "pending", null: false
    remove_column :documents, :extraction_error, :text
  end
end
