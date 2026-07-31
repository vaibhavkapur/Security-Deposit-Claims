# Stage 2 of the adjudication engine: classifies a claim's extracted line
# items against coverage rules, checks ledger-level eligibility patterns, and
# proposes a payout. Runs only when the claim has extracted line items
# (i.e. after DocumentExtraction has processed its documents).
#
# Coverage table sources:
#   - "There is no coverage for utility charge backs"          -> utility disallowed
#   - SDI forms credit back "ins, sd pro, utility" program fees -> insurance_fee disallowed
#   - "Can't charge lease break for military" (SCRA)            -> lease_break_fee reviewed
#   - core tenant-damage categories were routinely paid         -> allowed
#
# Ledger eligibility: "first full month rent never paid" was a hard historical
# decline. The ledger's payment rows let us flag it — flagged claims are
# declined under the binary conservative policy.
class LineItemReview
  # Binary conservative mapping: categories that historically needed human
  # review are denied rather than parked (reasons preserve the why).
  COVERAGE = {
    "unpaid_rent" => "allowed",
    "damage" => "allowed",
    "cleaning" => "allowed",
    "painting" => "allowed",
    "carpet_replacement" => "allowed",
    "rekey" => "allowed",
    "trash_removal" => "allowed",
    "reletting_fee" => "allowed",
    "notice_fee" => "allowed",
    "utility" => "denied",
    "insurance_fee" => "denied",
    "late_fee" => "denied",
    "admin_fee" => "denied",
    "lease_break_fee" => "denied",   # SCRA: not chargeable on military transfer
    "legal_fee" => "denied",
    "pet_fee" => "denied",
    "other" => "denied"
  }.freeze

  REASONS = {
    "unpaid_rent" => "unpaid rent is a covered charge",
    "damage" => "tenant damage is a covered charge",
    "cleaning" => "move-out cleaning is a covered charge",
    "painting" => "painting is a covered charge",
    "carpet_replacement" => "carpet replacement is a covered charge",
    "rekey" => "rekeying is a covered charge",
    "trash_removal" => "trash removal is a covered charge",
    "reletting_fee" => "reletting fee is a covered charge",
    "notice_fee" => "notice fee is a covered charge",
    "utility" => "utility charge-backs are not covered",
    "insurance_fee" => "program fees (renters insurance / SD protection) are not claimable",
    "lease_break_fee" => "not chargeable to servicemembers (SCRA); denied without verification",
    "late_fee" => "late fee coverage unverified",
    "admin_fee" => "admin fee coverage unverified",
    "legal_fee" => "legal fee coverage unverified",
    "pet_fee" => "pet fee coverage unverified",
    "other" => "unclassified charge"
  }.freeze
  DEFAULT_DENIAL_REASON = "excluded under conservative binary policy".freeze

  FIRST_MONTH_WINDOW_DAYS = 45

  def initialize(claim)
    @claim = claim
    @items = claim.claim_line_items.reload.to_a
  end

  def call
    return nil if @items.empty?

    classify_items

    if (flag = first_month_default_flag)
      return record("decline", reasons: [flag])
    end

    allowed = @items.select { |i| i.disposition == "allowed" && i.amount.positive? }.sum(&:amount)
    credits = @items.select { |i| i.amount.negative? && i.category.in?(%w[credit payment]) }.sum(&:amount)
    denied_total = @items.select { |i| i.disposition == "denied" && i.amount.positive? }.sum(&:amount)
    net_allowed = [allowed + credits, 0].max

    cap = @claim.policy&.max_benefit
    payout = cap ? [net_allowed, cap].min : net_allowed

    breakdown = "allowed #{allowed.to_f.round(2)}, credits #{credits.to_f.round(2)}, " \
                "cap #{cap&.to_f || 'none'} -> payout #{payout.to_f.round(2)}"
    if denied_total.positive?
      breakdown += "; #{denied_total.to_f.round(2)} in charges denied"
    end

    if payout.positive?
      record("approve", amount: payout, reasons: [breakdown])
    else
      record("decline", reasons: ["no allowable charges after review; #{breakdown}"])
    end
  end

  private

  def classify_items
    @items.each do |item|
      if item.amount.positive?
        disposition = COVERAGE.fetch(item.category, "denied")
        reason = REASONS.fetch(item.category, DEFAULT_DENIAL_REASON)
        item.update!(disposition: disposition, disposition_reason: reason)
      else
        # Credits/payments aren't claimed charges; they net against the payout.
        item.update!(disposition: "allowed", disposition_reason: "credit/payment nets against payout")
      end
    end
  end

  # Ledger shows activity in the lease's first month but no rent-sized payment:
  # the historical "first full month rent never paid" decline pattern.
  def first_month_default_flag
    start = @claim.lease.start_date
    rent = @claim.lease.monthly_rent
    return nil if start.nil? || rent.nil? || rent <= 0

    window = start..(start + FIRST_MONTH_WINDOW_DAYS)
    dated = @items.select { |i| i.txn_date.present? }
    return nil unless dated.any? { |i| window.cover?(i.txn_date) } # ledger doesn't cover move-in

    paid = dated.select { |i| i.amount.negative? && window.cover?(i.txn_date) }.sum(&:amount).abs
    return nil if paid >= rent * 0.5 # at least half a month received — no flag

    "possible first-month rent default: ledger covers move-in but shows only " \
      "#{paid.to_f.round(2)} received in first #{FIRST_MONTH_WINDOW_DAYS} days (rent #{rent.to_f.round(2)})"
  end

  # Overwrites the claim's single decision row with this engine's refined ruling.
  def record(outcome, reasons:, amount: nil)
    decision = AdjudicationDecision.find_or_initialize_by(claim: @claim)
    decision.update!(outcome: outcome, amount: amount, reason: reasons.join("; "))
    EligibilityEngine::Result.new(claim: @claim, outcome: outcome, amount: amount, reasons: reasons)
  end
end
