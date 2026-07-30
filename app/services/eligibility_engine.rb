# Stage 1 of the adjudication engine, using only data already in the
# database (no documents required).
#
# Rules are derived from the historical decline reasons and payout patterns
# in Claims.xlsx:
#   - duplicate claims were declined ("Duplicate claim.")
#   - claims without an identifiable policy were declined ("Not our policy.")
#   - approved amounts were min(claim_amount, max_benefit), paid in full for
#     evictions and trimmed after line-item review for move-outs
#
# Each claim gets exactly one decision row (approve | decline | refer | hold).
# This engine writes the first ruling; LineItemReview overwrites it with a
# refined one when extracted line items are available.
class EligibilityEngine
  Result = Struct.new(:claim, :outcome, :amount, :reasons, keyword_init: true)

  def initialize(claim)
    @claim = claim
  end

  def call
    referrals = referral_reasons
    if referrals.any?
      return record("refer", reasons: referrals)
    end

    if @claim.termination_type == "Eviction"
      # 87% of paid evictions received exactly max_benefit, regardless of the
      # claimed amount (lost rent accrues past the claim figure).
      record("approve", amount: @claim.policy.max_benefit,
             reasons: ["eviction: historically paid full max benefit (87% exact)"])
    else
      cap = [@claim.claim_amount, @claim.policy.max_benefit].min
      record("refer", amount: cap,
             reasons: ["move-out: line-item review required before payout " \
                       "(cap = min(claim #{@claim.claim_amount}, max benefit #{@claim.policy.max_benefit}))"])
    end
  end

  private

  def referral_reasons
    reasons = []
    if (dup = duplicate_of)
      # History shows some same-lease pairs were both paid (roommates,
      # re-filings), so a suspected duplicate goes to a human, not auto-decline.
      reasons << "possible duplicate of claim ##{dup.tracking_number} (same lease)"
    end
    reasons << "no policy on file" if @claim.policy.nil?
    reasons << "policy has no max benefit" if @claim.policy && @claim.policy.max_benefit.nil?
    reasons << "no claim amount" if @claim.claim_amount.nil?
    reasons << "claim amount is not positive" if @claim.claim_amount && @claim.claim_amount <= 0
    if @claim.claim_date && @claim.lease.start_date && @claim.claim_date < @claim.lease.start_date
      reasons << "claim filed before lease start (data error?)"
    end
    reasons << "flagged as exception in source data" if @claim.exception_flag
    reasons << "open hold reason: #{@claim.hold_reason.truncate(80)}" if @claim.hold_reason.present?
    reasons
  end

  def duplicate_of
    Claim.where(lease_id: @claim.lease_id).where("id < ?", @claim.id).first
  end

  def record(outcome, reasons:, amount: nil)
    decision = AdjudicationDecision.find_or_initialize_by(claim: @claim)
    decision.update!(outcome: outcome, amount: amount, reason: reasons.join("; "))
    Result.new(claim: @claim, outcome: outcome, amount: amount, reasons: reasons)
  end
end
