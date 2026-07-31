# Stage 1 of the adjudication engine, using only data already in the
# database (no documents required).
#
# Rules are derived from the historical decline reasons and payout patterns
# in Claims.xlsx:
#   - claims without an identifiable policy were declined ("Not our policy.")
#   - approved amounts were min(claim_amount, max_benefit), paid in full for
#     evictions and trimmed after line-item review for move-outs
#
# Each claim gets exactly one binary decision row (approve | decline).
# Conservative rule: anything not affirmatively supported is declined.
# Deny-wins: this engine's declines are final. LineItemReview (Stage 2) can
# overturn an approval to a decline on PDF evidence, never the reverse, and
# never changes an approved amount.
class EligibilityEngine
  Result = Struct.new(:claim, :outcome, :amount, :reasons, keyword_init: true)

  def initialize(claim)
    @claim = claim
  end

  def call
    problems = decline_reasons
    if problems.any?
      return record("decline", reasons: problems)
    end

    if @claim.termination_type == "Eviction"
      # 87% of paid evictions received exactly max_benefit, regardless of the
      # claimed amount (lost rent accrues past the claim figure).
      record("approve", amount: @claim.policy.max_benefit,
             reasons: ["eviction: historically paid full max benefit (87% exact)"])
    else
      # Move-out or blank termination: pay the claimed amount, capped at the
      # policy benefit (the historical min(claim_amount, max_benefit)
      # pattern). Stage 2 can still overturn on ledger evidence.
      amount = [@claim.claim_amount, @claim.policy.max_benefit].min
      reason = if @claim.claim_amount <= @claim.policy.max_benefit
        "claim amount #{@claim.claim_amount} within policy max benefit #{@claim.policy.max_benefit}"
      else
        "claim amount #{@claim.claim_amount} capped at policy max benefit #{@claim.policy.max_benefit}"
      end
      record("approve", amount: amount, reasons: [reason])
    end
  end

  private

  def decline_reasons
    reasons = []
    reasons << "no policy on file" if @claim.policy.nil?
    reasons << "policy has no max benefit" if @claim.policy && @claim.policy.max_benefit.nil?
    reasons << "no claim amount" if @claim.claim_amount.nil?
    reasons << "claim amount is not positive" if @claim.claim_amount && @claim.claim_amount <= 0
    if @claim.claim_date && @claim.lease.start_date && @claim.claim_date < @claim.lease.start_date
      reasons << "claim filed before lease start (data error?)"
    end
    reasons << "open hold reason: #{@claim.hold_reason.truncate(80)}" if @claim.hold_reason.present?
    reasons.concat(CommentRedFlags.for(@claim))
    reasons
  end

  def record(outcome, reasons:, amount: nil)
    decision = AdjudicationDecision.find_or_initialize_by(claim: @claim)
    decision.update!(outcome: outcome, amount: amount, reason: reasons.join("; "))
    Result.new(claim: @claim, outcome: outcome, amount: amount, reasons: reasons)
  end
end
