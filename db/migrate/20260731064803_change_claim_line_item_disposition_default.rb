class ChangeClaimLineItemDispositionDefault < ActiveRecord::Migration[7.1]
  def change
    # Binary dispositions: unreviewed charges are denied until review allows.
    change_column_default :claim_line_items, :disposition, from: "pending", to: "denied"
  end
end
