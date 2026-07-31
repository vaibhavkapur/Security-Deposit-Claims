require "test_helper"

class AdjudicationBatchTest < ActiveSupport::TestCase
  test "adjudicates every claim without a decision and returns the count" do
    claim_a = create_claim
    claim_b = create_claim(policy: nil)

    assert_equal 2, AdjudicationBatch.call

    assert_equal "approve", claim_a.reload.adjudication_decision.outcome
    assert_equal "decline", claim_b.reload.adjudication_decision.outcome
  end

  test "skips claims that already have a decision" do
    claim = create_claim
    create_decision(claim: claim, outcome: "decline", amount: nil, reason: "manual")

    assert_equal 0, AdjudicationBatch.call
    assert_equal "manual", claim.reload.adjudication_decision.reason
  end

  test "runs stage 2 for claims with line items so the ledger ruling wins" do
    claim = create_claim(termination_type: "Eviction",
                         policy: create_policy(max_benefit: 3000))
    create_line_item(claim: claim, category: "damage", amount: 750)

    AdjudicationBatch.call

    decision = claim.reload.adjudication_decision
    assert_equal "approve", decision.outcome
    # Stage 2 ledger payout (750) overrides the Stage 1 eviction rule (3000).
    assert_equal 750, decision.amount
  end

  test "is safe to re-run" do
    create_claim
    assert_equal 1, AdjudicationBatch.call
    assert_equal 0, AdjudicationBatch.call
    assert_equal 1, AdjudicationDecision.count
  end
end
