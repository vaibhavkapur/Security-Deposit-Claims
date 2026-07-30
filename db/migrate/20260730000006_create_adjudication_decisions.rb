class CreateAdjudicationDecisions < ActiveRecord::Migration[7.1]
  def change
    # Append-only audit trail: every rules-engine check, model proposal, and
    # human override. Rows are never updated or deleted (no updated_at).
    create_table :adjudication_decisions do |t|
      t.references :claim, null: false, foreign_key: true
      t.text :stage, null: false        # eligibility | amount | final
      t.text :decided_by, null: false   # "rules-engine v1" | reviewer name
      t.text :outcome, null: false      # approve | decline | refer | hold
      t.decimal :amount, precision: 10, scale: 2
      t.text :rule_or_reason, null: false
      t.timestamptz :decided_at, null: false, default: -> { "now()" }
      t.datetime :created_at, null: false
    end

    add_index :adjudication_decisions, %i[claim_id stage]
    add_index :adjudication_decisions, :outcome
  end
end
