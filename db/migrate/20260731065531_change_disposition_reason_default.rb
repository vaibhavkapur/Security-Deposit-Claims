class ChangeDispositionReasonDefault < ActiveRecord::Migration[7.1]
  def change
    # Every disposition carries a reason; fresh extractions are denied by
    # default until Stage 2 reviews them, so say exactly that.
    change_column_default :claim_line_items, :disposition_reason,
                          from: nil, to: "awaiting adjudication — denied by default"
    change_column_null :claim_line_items, :disposition_reason, false,
                       "awaiting adjudication — denied by default"
  end
end
