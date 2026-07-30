class CreateClaimActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :claim_activities do |t|
      # Nullable: comment threads from the spreadsheet export reference claims
      # by sheet position, which is unreliable (sheet was re-sorted after
      # export); threads stay unlinked until content proves the match.
      t.references :claim, foreign_key: true, null: true
      t.text :author, null: false
      t.text :body, null: false
      t.text :activity_type
      t.timestamptz :occurred_at, null: false
      t.text :source_row_ref
      t.text :link_method
      t.timestamps
    end

    add_index :claim_activities, %i[claim_id occurred_at]
    add_index :claim_activities, :source_row_ref
  end
end
