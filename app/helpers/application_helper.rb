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

  # Sample documents.extracted_json, shown in the tooltip next to the
  # documents table title. Mirrors DocumentExtraction::EXTRACTION_TOOL.
  SAMPLE_EXTRACTED_JSON = {
    "document_date" => "2025-11-03",
    "tenant_name" => "Jordan Rivera",
    "property_address" => "482 Elm St Apt 2C, Austin, TX",
    "total_amount" => 1685.00,
    "line_items" => [
      {"date" => "2025-11-01", "description" => "Unpaid rent - November", "category" => "unpaid_rent", "amount" => 1400.00},
      {"date" => "2025-11-03", "description" => "Carpet cleaning", "category" => "cleaning", "amount" => 285.00},
      {"date" => "2025-11-03", "description" => "Security deposit applied", "category" => "credit", "amount" => -500.00}
    ],
    "notes" => "Ledger page 2 partially illegible"
  }.freeze

  def sample_extracted_json
    JSON.pretty_generate(SAMPLE_EXTRACTED_JSON)
  end

  # [category, disposition, reason] rows for the claim_line_items tooltip,
  # straight from the Stage 2 rules.
  def line_item_disposition_rules
    LineItemReview::COVERAGE.map do |category, disposition|
      [category, disposition, LineItemReview::REASONS.fetch(category, LineItemReview::DEFAULT_DENIAL_REASON)]
    end
  end

  # Demo narrative for the adjudication_decisions tooltip: the two engine
  # stages that produce each claim's single approve/decline row, in the order
  # they run. Mirrors EligibilityEngine and LineItemReview.
  ADJUDICATION_FLOW = [
    {
      heading: "Stage 1 — Spreadsheet extraction",
      groups: [
        {
          label: "approve",
          items: [
            "full policy benefit if eviction (claims.termination_type)",
            "claim amount, capped at max benefit, if termination_type is blank"
          ]
        },
        {
          label: "deny",
          items: [
            %(no policy, or blank "Max Benefit"),
            %("Amount of Claim" blank or ≤ 0),
            %(hold_reason ("Hold Reason" non-empty)),
            "red-flag comments: do-not-pay / dispute / attorney / fraud",
            "an explicit non-eviction termination_type (move-out etc.)"
          ]
        }
      ]
    },
    {
      heading: "Stage 2 — PDF extraction",
      intro: "deny-wins: reviews Stage 1 approvals only — a decline is final; " \
             "payout = allowed line items − credits",
      groups: [
        {
          label: "approve",
          items: [
            "payout > 0 → the Stage 1 approval stands, at the Stage 1 amount"
          ]
        },
        {
          label: "deny",
          items: [
            "red-flag comments: do-not-pay / dispute / attorney / fraud",
            "first month's rent never paid (ledger)",
            "payout ≤ 0"
          ]
        }
      ]
    }
  ].freeze
end
