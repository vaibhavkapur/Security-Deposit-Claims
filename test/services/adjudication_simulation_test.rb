require "test_helper"

class AdjudicationSimulationTest < ActiveSupport::TestCase
  def scenario(result, name)
    result.scenarios.find { |s| s.name.include?(name) } ||
      flunk("no scenario matching #{name.inspect}")
  end

  test "only sheet-decided claims with decisions enter the simulation" do
    approved = create_claim(status: "Approved", approved_benefit_amount: 2000)
    create_decision(claim: approved, outcome: "approve", amount: 2000,
                    reason: "claim amount 2000.0 within policy max benefit 3000.0")

    open_claim = create_claim(status: "HOLD")
    create_decision(claim: open_claim, outcome: "approve", amount: 100, reason: "r")
    create_claim(status: "Approved") # decided by sheet, but no decision row

    result = AdjudicationSimulation.new.call
    current = scenario(result, "Current rules")

    # Only the Approved+decided claim counts: 1 approval / 1 fact = 100%.
    assert_in_delta 100.0, current.approval_rate
  end

  test "current rules scenario reproduces the stored decisions" do
    a = create_claim(status: "Approved", approved_benefit_amount: 2000, claim_amount: 2000)
    create_decision(claim: a, outcome: "approve", amount: 2000,
                    reason: "claim amount 2000.0 within policy max benefit 3000.0")

    b = create_claim(status: "Declined", policy: nil)
    create_decision(claim: b, outcome: "decline", amount: nil, reason: "no policy on file")

    c = create_claim(status: "Approved", approved_benefit_amount: 1000, claim_amount: nil)
    create_decision(claim: c, outcome: "decline", amount: nil, reason: "no claim amount")

    current = scenario(AdjudicationSimulation.new.call, "Current rules")

    assert_in_delta 100.0 * 1 / 3, current.approval_rate
    assert_in_delta 100.0 * 2 / 3, current.agreement_rate
    assert_equal 1, current.both_approved
    assert_in_delta 100.0, current.exact_pct
    assert_in_delta 2000.0, current.my_total
    assert_in_delta 0.0, current.mae
  end

  test "pay_missing_at_max toggle revives no-claim-amount declines at max benefit" do
    c = create_claim(status: "Approved", approved_benefit_amount: 1000, claim_amount: nil,
                     policy: create_policy(max_benefit: 3000))
    create_decision(claim: c, outcome: "decline", amount: nil, reason: "no claim amount")

    result = AdjudicationSimulation.new.call
    current = scenario(result, "Current rules")
    variant = scenario(result, "missing claim amount")

    assert_in_delta 0.0, current.approval_rate
    assert_in_delta 100.0, variant.approval_rate
    assert_in_delta 100.0, variant.agreement_rate
    assert_equal 1, variant.both_approved
    # Paid at max benefit (3000) vs sheet amount 1000.
    assert_in_delta 3000.0, variant.my_total
    assert_in_delta 2000.0, variant.mae
    assert_in_delta 0.0, variant.exact_pct
  end

  test "hard gates like no policy survive every scenario" do
    b = create_claim(status: "Declined", policy: nil)
    create_decision(claim: b, outcome: "decline", amount: nil, reason: "no policy on file")

    result = AdjudicationSimulation.new.call
    result.scenarios.each do |s|
      assert_in_delta 0.0, s.approval_rate, 0.001, "scenario #{s.name} should keep the decline"
    end
  end

  test "max_for_all scenario prices every approval at max benefit" do
    a = create_claim(status: "Approved", approved_benefit_amount: 2000, claim_amount: 2000,
                     policy: create_policy(max_benefit: 3000))
    create_decision(claim: a, outcome: "approve", amount: 2000,
                    reason: "claim amount 2000.0 within policy max benefit 3000.0")

    maxed = scenario(AdjudicationSimulation.new.call, "every approval priced at max")

    assert_in_delta 3000.0, maxed.my_total
    assert_in_delta 1000.0, maxed.mae
  end

  test "ignore_flags_holds toggle revives hold and comment-flag declines" do
    d = create_claim(status: "Approved", approved_benefit_amount: 3000, claim_amount: 2500,
                     policy: create_policy(max_benefit: 3000), hold_reason: "waiting on docs")
    create_decision(claim: d, outcome: "decline", amount: nil,
                    reason: %(open hold reason: waiting on docs; comments flag — tenant dispute: "disputing"))

    result = AdjudicationSimulation.new.call
    current = scenario(result, "Current rules")
    maxed = scenario(result, "every approval priced at max")

    assert_in_delta 0.0, current.approval_rate
    assert_in_delta 100.0, maxed.approval_rate
    assert_in_delta 3000.0, maxed.my_total
    assert_in_delta 100.0, maxed.exact_pct
  end

  test "evictions replay at max benefit" do
    e = create_claim(status: "Approved", approved_benefit_amount: 3000, claim_amount: 500,
                     termination_type: "Eviction", policy: create_policy(max_benefit: 3000))
    create_decision(claim: e, outcome: "approve", amount: 3000,
                    reason: "eviction: historically paid full max benefit (87% exact)")

    current = scenario(AdjudicationSimulation.new.call, "Current rules")
    assert_in_delta 100.0, current.exact_pct
    assert_in_delta 3000.0, current.my_total
  end

  test "stage 2 ledger payout replays from the line items" do
    claim = create_claim(status: "Approved", approved_benefit_amount: 500,
                         policy: create_policy(max_benefit: 3000))
    create_line_item(claim: claim, category: "damage", amount: 800, disposition: "allowed",
                     disposition_reason: "covered")
    create_line_item(claim: claim, category: "payment", amount: -300, disposition: "allowed",
                     disposition_reason: "credit")
    create_decision(claim: claim, outcome: "approve", amount: 500,
                    reason: "ledger shows a recoverable balance (allowed charges exceed credits)")

    current = scenario(AdjudicationSimulation.new.call, "Current rules")
    assert_in_delta 100.0, current.exact_pct
    assert_in_delta 500.0, current.my_total
  end

  # -- oracle ceiling ---------------------------------------------------------

  test "oracle counts sheet amounts reachable by any candidate formula" do
    matched = create_claim(status: "Approved", approved_benefit_amount: 2000, claim_amount: 2000)
    create_decision(claim: matched, outcome: "approve", amount: 2000, reason: "r")

    unmatched = create_claim(status: "Approved", approved_benefit_amount: 777, claim_amount: 500,
                             policy: create_policy(max_benefit: 3000))
    create_decision(claim: unmatched, outcome: "approve", amount: 500, reason: "r")

    oracle = AdjudicationSimulation.new.call.oracle

    assert_equal 2, oracle[:total]
    assert_equal 1, oracle[:matched]
    assert_equal 1, oracle[:unmatched]
    assert_in_delta 50.0, oracle[:pct]
    assert_equal 1, oracle[:unmatched_without_items]
  end

  test "oracle matches sheet amounts equal to the max benefit" do
    claim = create_claim(status: "Approved", approved_benefit_amount: 3000, claim_amount: 500,
                         policy: create_policy(max_benefit: 3000))
    create_decision(claim: claim, outcome: "approve", amount: 500, reason: "r")

    oracle = AdjudicationSimulation.new.call.oracle
    assert_equal 1, oracle[:matched]
  end

  test "oracle only considers rows both sides approved and priced" do
    declined = create_claim(status: "Declined")
    create_decision(claim: declined, outcome: "decline", amount: nil, reason: "no policy on file")
    unpriced = create_claim(status: "Approved", approved_benefit_amount: nil)
    create_decision(claim: unpriced, outcome: "approve", amount: 100, reason: "r")

    oracle = AdjudicationSimulation.new.call.oracle
    assert_equal 0, oracle[:total]
  end

  test "returns the three cumulative scenarios in order" do
    claim = create_claim(status: "Approved", approved_benefit_amount: 100, claim_amount: 100)
    create_decision(claim: claim, outcome: "approve", amount: 100, reason: "r")

    names = AdjudicationSimulation.new.call.scenarios.map(&:name)
    assert_equal 3, names.size
    assert_equal "Current rules", names.first
  end
end
