class CreateClaimLineItems < ActiveRecord::Migration[7.1]
  def change
    create_table :claim_line_items do |t|
      t.references :claim, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true # provenance
      t.date :txn_date
      t.text :category, null: false   # damage, cleaning, unpaid_rent, late_fee, utility, ...
      t.text :description, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.text :disposition, null: false, default: "pending"
      # pending | allowed | disallowed | needs_review
      t.text :disposition_reason
      t.timestamps
    end

    add_index :claim_line_items, %i[claim_id disposition]
  end
end
