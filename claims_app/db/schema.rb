# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_07_30_000006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "adjudication_decisions", force: :cascade do |t|
    t.bigint "claim_id", null: false
    t.text "stage", null: false
    t.text "decided_by", null: false
    t.text "outcome", null: false
    t.decimal "amount", precision: 10, scale: 2
    t.text "rule_or_reason", null: false
    t.timestamptz "decided_at", default: -> { "now()" }, null: false
    t.datetime "created_at", null: false
    t.index ["claim_id", "stage"], name: "index_adjudication_decisions_on_claim_id_and_stage"
    t.index ["claim_id"], name: "index_adjudication_decisions_on_claim_id"
    t.index ["outcome"], name: "index_adjudication_decisions_on_outcome"
  end

  create_table "claim_activities", force: :cascade do |t|
    t.bigint "claim_id"
    t.text "author", null: false
    t.text "body", null: false
    t.text "activity_type"
    t.timestamptz "occurred_at", null: false
    t.text "source_row_ref"
    t.text "link_method"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id", "occurred_at"], name: "index_claim_activities_on_claim_id_and_occurred_at"
    t.index ["claim_id"], name: "index_claim_activities_on_claim_id"
    t.index ["source_row_ref"], name: "index_claim_activities_on_source_row_ref"
  end

  create_table "claim_line_items", force: :cascade do |t|
    t.bigint "claim_id", null: false
    t.bigint "document_id", null: false
    t.date "txn_date"
    t.text "category", null: false
    t.text "description", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.text "disposition", default: "pending", null: false
    t.text "disposition_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id", "disposition"], name: "index_claim_line_items_on_claim_id_and_disposition"
    t.index ["claim_id"], name: "index_claim_line_items_on_claim_id"
    t.index ["document_id"], name: "index_claim_line_items_on_document_id"
  end

  create_table "claims", force: :cascade do |t|
    t.bigint "lease_id", null: false
    t.bigint "policy_id"
    t.text "tracking_number", null: false
    t.date "claim_date"
    t.decimal "claim_amount", precision: 10, scale: 2
    t.text "termination_type"
    t.text "status"
    t.text "pending_docs_from_pm"
    t.date "approval_date"
    t.decimal "approved_benefit_amount", precision: 10, scale: 2
    t.text "approved_benefit_note"
    t.text "pm_explanation"
    t.text "hold_reason"
    t.date "posted_date"
    t.date "pm_notified_at"
    t.boolean "audit_selected", default: false, null: false
    t.boolean "exception_flag", default: false, null: false
    t.boolean "needs_adjudication_review"
    t.boolean "tenant_info_reviewed"
    t.boolean "policy_info_updated"
    t.boolean "pm_info_viewed"
    t.boolean "collections_opened"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lease_id"], name: "index_claims_on_lease_id"
    t.index ["policy_id"], name: "index_claims_on_policy_id"
    t.index ["status"], name: "index_claims_on_status"
    t.index ["tracking_number"], name: "index_claims_on_tracking_number", unique: true
  end

  create_table "collections", force: :cascade do |t|
    t.bigint "claim_id", null: false
    t.timestamptz "referred_at"
    t.text "collection_status"
    t.text "tenant_contacted_methods"
    t.text "tenant_collection_status"
    t.decimal "settlement_amount", precision: 10, scale: 2
    t.date "settlement_date"
    t.date "collected_date"
    t.decimal "collected_amount", precision: 10, scale: 2
    t.date "collection_processed_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["claim_id"], name: "index_collections_on_claim_id", unique: true
    t.index ["collection_status"], name: "index_collections_on_collection_status"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "claim_id", null: false
    t.text "original_name", null: false
    t.text "relative_path", null: false
    t.string "content_hash", limit: 64, null: false
    t.text "mime_type"
    t.bigint "byte_size", null: false
    t.text "doc_type"
    t.text "doc_type_source"
    t.text "storage_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "extraction_status", default: "pending", null: false
    t.jsonb "extracted_json"
    t.timestamptz "extracted_at"
    t.text "extractor_version"
    t.text "extraction_error"
    t.index ["claim_id"], name: "index_documents_on_claim_id"
    t.index ["content_hash"], name: "index_documents_on_content_hash", unique: true
    t.index ["doc_type"], name: "index_documents_on_doc_type"
    t.index ["extraction_status"], name: "index_documents_on_extraction_status"
  end

  create_table "leases", force: :cascade do |t|
    t.bigint "property_id", null: false
    t.bigint "property_manager_id"
    t.date "start_date"
    t.date "end_date"
    t.date "move_out_date"
    t.decimal "monthly_rent", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_leases_on_property_id"
    t.index ["property_manager_id"], name: "index_leases_on_property_manager_id"
  end

  create_table "pm_companies", force: :cascade do |t|
    t.text "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_pm_companies_on_name", unique: true
  end

  create_table "policies", force: :cascade do |t|
    t.text "policy_number", null: false
    t.text "group_number"
    t.text "treaty_number"
    t.decimal "max_benefit", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["policy_number"], name: "index_policies_on_policy_number", unique: true
  end

  create_table "properties", force: :cascade do |t|
    t.text "street_address", null: false
    t.text "city"
    t.string "state", limit: 2
    t.string "zip", limit: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["street_address", "city", "state", "zip"], name: "idx_properties_address", unique: true, nulls_not_distinct: true
  end

  create_table "property_managers", force: :cascade do |t|
    t.bigint "pm_company_id", null: false
    t.text "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pm_company_id", "name"], name: "index_property_managers_on_pm_company_id_and_name", unique: true
    t.index ["pm_company_id"], name: "index_property_managers_on_pm_company_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.bigint "lease_id", null: false
    t.integer "tenant_number", limit: 2, null: false
    t.text "relationship"
    t.text "employer_name"
    t.string "employer_phone", limit: 20
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lease_id", "tenant_number"], name: "index_tenants_on_lease_id_and_tenant_number", unique: true
    t.index ["lease_id"], name: "index_tenants_on_lease_id"
  end

  add_foreign_key "adjudication_decisions", "claims"
  add_foreign_key "claim_activities", "claims"
  add_foreign_key "claim_line_items", "claims"
  add_foreign_key "claim_line_items", "documents"
  add_foreign_key "claims", "leases"
  add_foreign_key "claims", "policies"
  add_foreign_key "collections", "claims"
  add_foreign_key "documents", "claims"
  add_foreign_key "leases", "properties"
  add_foreign_key "leases", "property_managers"
  add_foreign_key "property_managers", "pm_companies"
  add_foreign_key "tenants", "leases"
end
