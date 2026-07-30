class CreateClaimsSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :pm_companies do |t|
      t.text :name, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :property_managers do |t|
      t.references :pm_company, null: false, foreign_key: true
      t.text :name, null: false
      t.timestamps
    end
    add_index :property_managers, [:pm_company_id, :name], unique: true

    create_table :properties do |t|
      t.text :street_address, null: false
      t.text :city
      t.string :state, limit: 2
      t.string :zip, limit: 10
      t.timestamps
    end
    add_index :properties, [:street_address, :city, :state, :zip],
              unique: true, name: "idx_properties_address", nulls_not_distinct: true

    create_table :policies do |t|
      t.text :policy_number, null: false, index: { unique: true }
      t.text :group_number
      t.text :treaty_number
      t.decimal :max_benefit, precision: 10, scale: 2
      t.timestamps
    end

    create_table :leases do |t|
      t.references :property, null: false, foreign_key: true
      t.references :property_manager, foreign_key: true
      t.date :start_date
      t.date :end_date
      t.date :move_out_date
      t.decimal :monthly_rent, precision: 10, scale: 2
      t.timestamps
    end

    create_table :tenants do |t|
      t.references :lease, null: false, foreign_key: true
      t.integer :tenant_number, limit: 2, null: false
      t.text :relationship
      t.text :employer_name
      t.string :employer_phone, limit: 20
      t.timestamps
    end
    add_index :tenants, [:lease_id, :tenant_number], unique: true

    create_table :claims do |t|
      t.references :lease, null: false, foreign_key: true
      t.references :policy, foreign_key: true
      t.text :tracking_number, null: false, index: { unique: true }
      t.date :claim_date
      t.decimal :claim_amount, precision: 10, scale: 2
      t.text :termination_type
      t.text :status, index: true
      t.text :pending_docs_from_pm
      t.date :approval_date
      t.decimal :approved_benefit_amount, precision: 10, scale: 2
      t.text :approved_benefit_note
      t.text :pm_explanation
      t.text :hold_reason
      t.date :posted_date
      t.date :pm_notified_at
      t.boolean :audit_selected, null: false, default: false
      t.boolean :exception_flag, null: false, default: false
      t.boolean :needs_adjudication_review
      t.boolean :tenant_info_reviewed
      t.boolean :policy_info_updated
      t.boolean :pm_info_viewed
      t.boolean :collections_opened
      t.timestamps
    end

    create_table :collections do |t|
      t.references :claim, null: false, foreign_key: true, index: { unique: true }
      t.timestamptz :referred_at
      t.text :collection_status, index: true
      t.text :tenant_contacted_methods
      t.text :tenant_collection_status
      t.decimal :settlement_amount, precision: 10, scale: 2
      t.date :settlement_date
      t.date :collected_date
      t.decimal :collected_amount, precision: 10, scale: 2
      t.date :collection_processed_date
      t.timestamps
    end
  end
end
