class CreateDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :documents do |t|
      t.references :claim, null: false, foreign_key: true
      t.text :original_name, null: false
      t.text :relative_path, null: false     # path inside the uploaded zip
      t.string :content_hash, limit: 64, null: false
      t.text :mime_type
      t.bigint :byte_size, null: false
      t.text :doc_type                       # ledger, lease, sdi_form, ...
      t.text :doc_type_source                # filename | model | human
      t.text :storage_key, null: false       # relative path under storage/
      t.timestamps
    end

    add_index :documents, :content_hash, unique: true
    add_index :documents, :doc_type
  end
end
