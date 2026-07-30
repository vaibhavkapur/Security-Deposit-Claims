class SimplifyAdjudicationDecisions < ActiveRecord::Migration[7.1]
  def up
    # Collapse the append-only history to one decision per claim, keeping the
    # newest row (the most-refined ruling — matches what the UI displayed).
    execute <<~SQL
      DELETE FROM adjudication_decisions a
      USING adjudication_decisions b
      WHERE a.claim_id = b.claim_id AND a.id < b.id
    SQL

    remove_column :adjudication_decisions, :stage
    remove_column :adjudication_decisions, :decided_by
    remove_column :adjudication_decisions, :decided_at
    rename_column :adjudication_decisions, :rule_or_reason, :reason

    remove_index :adjudication_decisions, :claim_id
    add_index :adjudication_decisions, :claim_id, unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
