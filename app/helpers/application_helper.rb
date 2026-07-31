module ApplicationHelper
  LINK_METHOD_LABELS = {
    "explicit_ref" => "Thread linked via an explicit #tracking reference in the comments.",
    "address" => "Thread linked via a street address unique to this claim.",
    "approval_amount" => "Thread linked via an approval amount unique to this claim.",
    "tenant_name" => "Thread linked via a tenant name from this claim's documents."
  }.freeze

  def link_method_label(method)
    LINK_METHOD_LABELS[method] || method
  end

  # jsonb loses key order (Postgres sorts keys by length), which floats
  # "notes" above the extraction content. Reorder for display: header fields,
  # then line items, notes last, any unknown keys in between.
  JSON_DISPLAY_ORDER = %w[document_date tenant_name property_address
                          total_amount line_items notes].freeze

  def json_for_display(value)
    return value unless value.is_a?(Hash)

    value.sort_by { |key, _| [JSON_DISPLAY_ORDER.index(key) || JSON_DISPLAY_ORDER.index("notes") - 0.5, key] }.to_h
  end
end
