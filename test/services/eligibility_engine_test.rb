require "test_helper"

class EligibilityEngineTest < ActiveSupport::TestCase
  # -- decline gates ---------------------------------------------------------

  test "declines when there is no policy on file" do
    claim = create_claim(policy: nil)
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_nil result.amount
    assert_includes result.reasons, "no policy on file"
  end

  test "declines when the policy has no max benefit" do
    claim = create_claim(policy: create_policy(max_benefit: nil))
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_includes result.reasons, "policy has no max benefit"
  end

  test "declines when there is no claim amount" do
    claim = create_claim(claim_amount: nil)
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_includes result.reasons, "no claim amount"
  end

  test "declines when the claim amount is zero" do
    claim = create_claim(claim_amount: 0)
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_includes result.reasons, "claim amount is not positive"
  end

  test "declines when the claim amount is negative" do
    claim = create_claim(claim_amount: -50)
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_includes result.reasons, "claim amount is not positive"
  end

  test "declines when the claim was filed before the lease started" do
    lease = create_lease(start_date: Date.new(2025, 3, 1))
    claim = create_claim(lease: lease, claim_date: Date.new(2025, 2, 1))
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_includes result.reasons, "claim filed before lease start (data error?)"
  end

  test "does not apply the pre-lease gate when claim date or lease start is missing" do
    lease = create_lease(start_date: nil)
    claim = create_claim(lease: lease, claim_date: Date.new(2025, 2, 1))
    assert_equal "approve", EligibilityEngine.new(claim).call.outcome

    claim2 = create_claim(claim_date: nil)
    assert_equal "approve", EligibilityEngine.new(claim2).call.outcome
  end

  test "declines when the claim has an open hold reason" do
    claim = create_claim(hold_reason: "Waiting on signed lease from PM")
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_match(/\Aopen hold reason: Waiting on signed lease/, result.reasons.first)
  end

  test "truncates long hold reasons in the decline reason" do
    claim = create_claim(hold_reason: "z" * 200)
    result = EligibilityEngine.new(claim).call
    assert_operator result.reasons.first.length, :<, 120
  end

  test "declines when comments contain red flags" do
    claim = create_claim
    create_activity(claim: claim, body: "tenant is disputing all charges")
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_match(/tenant dispute/, result.reasons.first)
  end

  test "collects multiple decline reasons" do
    claim = create_claim(policy: nil, claim_amount: nil, hold_reason: "hold it")
    result = EligibilityEngine.new(claim).call

    assert_equal "decline", result.outcome
    assert_equal 3, result.reasons.size
    decision = claim.reload.adjudication_decision
    assert_equal result.reasons.join("; "), decision.reason
  end

  # -- approvals -------------------------------------------------------------

  test "approves evictions at full max benefit regardless of claim amount" do
    claim = create_claim(termination_type: "Eviction", claim_amount: 500,
                         policy: create_policy(max_benefit: 3000))
    result = EligibilityEngine.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 3000, result.amount
    assert_match(/eviction: historically paid full max benefit/, result.reasons.first)
  end

  test "approves move-outs at the claim amount when within max benefit" do
    claim = create_claim(termination_type: "Move-Out", claim_amount: 1200,
                         policy: create_policy(max_benefit: 3000))
    result = EligibilityEngine.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 1200, result.amount
    assert_match(/within policy max benefit/, result.reasons.first)
  end

  test "caps move-out approvals at the policy max benefit" do
    claim = create_claim(termination_type: "Move-Out", claim_amount: 5000,
                         policy: create_policy(max_benefit: 3000))
    result = EligibilityEngine.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 3000, result.amount
    assert_match(/capped at policy max benefit/, result.reasons.first)
  end

  test "treats blank termination type like a move-out" do
    claim = create_claim(termination_type: nil, claim_amount: 1800,
                         policy: create_policy(max_benefit: 3000))
    result = EligibilityEngine.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 1800, result.amount
  end

  # -- decision persistence ----------------------------------------------------

  test "persists exactly one decision row per claim" do
    claim = create_claim
    EligibilityEngine.new(claim).call

    decision = claim.reload.adjudication_decision
    assert_equal "approve", decision.outcome
    assert_equal 2000, decision.amount
  end

  test "re-running updates the existing decision instead of creating another" do
    claim = create_claim
    EligibilityEngine.new(claim).call
    first_id = claim.reload.adjudication_decision.id

    claim.update!(claim_amount: nil)
    result = EligibilityEngine.new(claim.reload).call

    assert_equal "decline", result.outcome
    assert_equal first_id, claim.reload.adjudication_decision.id
    assert_equal 1, AdjudicationDecision.where(claim: claim).count
  end
end
