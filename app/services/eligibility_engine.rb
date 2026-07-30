# Stage 1 + Stage 2 of the adjudication engine, using only data already in
# the database (no documents required).
#
# Rules are derived from the historical decline reasons and payout patterns
# in Claims.xlsx:
#   - duplicate claims were declined ("Duplicate claim.")
#   - claims without an identifiable policy were declined ("Not our policy.")
#   - approved amounts were min(claim_amount, max_benefit), paid in full for
#     evictions and trimmed after line-item review for move-outs
#
# Decision flow per claim:
#   eligibility: decline (hard rule failed) | refer (can't auto-decide) | approve
#   amount:      propose min(claim_amount, max_benefit)
#   final:       approve at cap for evictions; refer move-outs to line-item review
#
# Every decision is appended to adjudication_decisions; nothing is updated.
class EligibilityEngine
  VERSION = "rules-engine v1".freeze

  Result = Struct.new(:claim, :outcome, :amount, :reasons, keyword_init: true)

  def initialize(claim, decided_by: VERSION)
    @claim = claim
    @decided_by = decided_by
  end

  def call
    referrals = referral_reasons
    if referrals.any?
      return record("eligibility", "refer", reasons: referrals)
    end

    record("eligibility", "approve", reasons: ["all eligibility rules passed"])

    if @claim.termination_type == "Eviction"
      # 87% of paid evictions received exactly max_benefit, regardless of the
      # claimed amount (lost rent accrues past the claim figure).
      payout = @claim.policy.max_benefit
      record("amount", "approve", amount: payout, reasons: ["eviction: full max benefit"])
      record("final", "approve", amount: payout,
             reasons: ["eviction: historically paid full max benefit (87% exact)"])
    else
      cap = [@claim.claim_amount, @claim.policy.max_benefit].min
      record("amount", "approve", amount: cap,
             reasons: ["cap = min(claim #{@claim.claim_amount}, max benefit #{@claim.policy.max_benefit})"])
      record("final", "refer", amount: cap,
             reasons: ["move-out: line-item review required before payout (historical median 91% of cap)"])
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

  def record(stage, outcome, reasons:, amount: nil)
    AdjudicationDecision.create!(
      claim: @claim,
      stage: stage,
      decided_by: @decided_by,
      outcome: outcome,
      amount: amount,
      rule_or_reason: reasons.join("; ")
    )
    Result.new(claim: @claim, outcome: outcome, amount: amount, reasons: reasons)
  end
end
