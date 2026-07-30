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
end
