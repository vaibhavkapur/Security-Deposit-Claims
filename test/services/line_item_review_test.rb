require "test_helper"

class LineItemReviewTest < ActiveSupport::TestCase
  ALLOWED_CATEGORIES = %w[
    unpaid_rent damage cleaning painting carpet_replacement rekey
    trash_removal reletting_fee notice_fee
  ].freeze
  DENIED_CATEGORIES = %w[
    utility insurance_fee late_fee admin_fee lease_break_fee legal_fee
    pet_fee other
  ].freeze

  test "returns nil and leaves the decision untouched when the claim has no line items" do
    claim = create_claim
    create_decision(claim: claim, outcome: "approve", amount: 999, reason: "stage 1")

    assert_nil LineItemReview.new(claim).call
    assert_equal 999, claim.reload.adjudication_decision.amount
  end

  # -- classification ----------------------------------------------------------

  test "marks covered categories allowed with their coverage reason" do
    claim = create_claim
    items = ALLOWED_CATEGORIES.map { |cat| create_line_item(claim: claim, category: cat, amount: 10) }

    LineItemReview.new(claim).call

    items.each do |item|
      item.reload
      assert_equal "allowed", item.disposition, "#{item.category} should be allowed"
      refute_equal LineItemReview::DEFAULT_DENIAL_REASON, item.disposition_reason
    end
  end

  test "marks excluded categories denied with their reason" do
    claim = create_claim
    items = DENIED_CATEGORIES.map { |cat| create_line_item(claim: claim, category: cat, amount: 10) }

    LineItemReview.new(claim).call

    items.each do |item|
      item.reload
      assert_equal "denied", item.disposition, "#{item.category} should be denied"
    end
  end

  test "denies unknown categories with the default reason" do
    claim = create_claim
    item = create_line_item(claim: claim, category: "mystery_fee", amount: 10)

    LineItemReview.new(claim).call

    assert_equal "denied", item.reload.disposition
    assert_equal LineItemReview::DEFAULT_DENIAL_REASON, item.disposition_reason
  end

  test "marks negative amounts allowed as credits regardless of category" do
    claim = create_claim
    credit = create_line_item(claim: claim, category: "payment", amount: -500)
    create_line_item(claim: claim, category: "damage", amount: 600)

    LineItemReview.new(claim).call

    assert_equal "allowed", credit.reload.disposition
    assert_match(/credit\/payment nets against payout/, credit.disposition_reason)
  end

  # -- payout math -------------------------------------------------------------

  test "approves at the sum of allowed charges" do
    claim = create_claim(policy: create_policy(max_benefit: 5000))
    create_line_item(claim: claim, category: "damage", amount: 800)
    create_line_item(claim: claim, category: "cleaning", amount: 200)
    create_line_item(claim: claim, category: "late_fee", amount: 300) # denied

    result = LineItemReview.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 1000, result.amount
    assert_match(/ledger shows a recoverable balance/, result.reasons.first)
  end

  test "nets credit and payment rows against the payout" do
    claim = create_claim(policy: create_policy(max_benefit: 5000))
    create_line_item(claim: claim, category: "unpaid_rent", amount: 1500)
    create_line_item(claim: claim, category: "payment", amount: -400)
    create_line_item(claim: claim, category: "credit", amount: -100)

    result = LineItemReview.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 1000, result.amount
  end

  test "negative rows in non-credit categories do not net against the payout" do
    claim = create_claim(policy: create_policy(max_benefit: 5000))
    create_line_item(claim: claim, category: "damage", amount: 700)
    create_line_item(claim: claim, category: "damage", amount: -300)

    result = LineItemReview.new(claim).call

    assert_equal 700, result.amount
  end

  test "caps the payout at the policy max benefit" do
    claim = create_claim(policy: create_policy(max_benefit: 1000))
    create_line_item(claim: claim, category: "damage", amount: 2500)

    result = LineItemReview.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 1000, result.amount
  end

  test "pays the uncapped ledger balance when the policy has no max benefit" do
    claim = create_claim(policy: create_policy(max_benefit: nil))
    create_line_item(claim: claim, category: "damage", amount: 2500)

    result = LineItemReview.new(claim).call

    assert_equal 2500, result.amount
  end

  test "declines when credits cover all allowed charges" do
    claim = create_claim
    create_line_item(claim: claim, category: "damage", amount: 300)
    create_line_item(claim: claim, category: "payment", amount: -300)

    result = LineItemReview.new(claim).call

    assert_equal "decline", result.outcome
    assert_nil result.amount
    assert_match(/no recoverable balance in ledger/, result.reasons.first)
  end

  test "declines when every charge is in a denied category" do
    claim = create_claim
    create_line_item(claim: claim, category: "late_fee", amount: 300)

    result = LineItemReview.new(claim).call

    assert_equal "decline", result.outcome
  end

  # -- red flags ----------------------------------------------------------------

  test "declines on comment red flags even with a recoverable ledger" do
    claim = create_claim
    create_line_item(claim: claim, category: "damage", amount: 500)
    create_activity(claim: claim, body: "do not pay, suspected fraud")

    result = LineItemReview.new(claim).call

    assert_equal "decline", result.outcome
    assert result.reasons.all? { |r| r.start_with?("comments flag") }
  end

  test "still classifies items before declining on red flags" do
    claim = create_claim
    item = create_line_item(claim: claim, category: "damage", amount: 500)
    create_activity(claim: claim, body: "tenant dispute ongoing")

    LineItemReview.new(claim).call

    assert_equal "allowed", item.reload.disposition
  end

  # -- first-month rent default flag ---------------------------------------------

  test "declines when the ledger covers move-in but shows no first-month payment" do
    lease = create_lease(start_date: Date.new(2025, 1, 1), monthly_rent: 1500)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "unpaid_rent", amount: 1500,
                     txn_date: Date.new(2025, 1, 5))

    result = LineItemReview.new(claim).call

    assert_equal "decline", result.outcome
    assert_match(/possible first-month rent default/, result.reasons.first)
  end

  test "does not flag when at least half a month's rent was received in the window" do
    lease = create_lease(start_date: Date.new(2025, 1, 1), monthly_rent: 1500)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "unpaid_rent", amount: 1500,
                     txn_date: Date.new(2025, 1, 5))
    create_line_item(claim: claim, category: "payment", amount: -750,
                     txn_date: Date.new(2025, 1, 10))

    result = LineItemReview.new(claim).call

    assert_equal "approve", result.outcome
    assert_equal 750, result.amount
  end

  test "does not flag when the ledger does not cover the move-in window" do
    lease = create_lease(start_date: Date.new(2025, 1, 1), monthly_rent: 1500)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "damage", amount: 400,
                     txn_date: Date.new(2025, 6, 1))

    result = LineItemReview.new(claim).call

    assert_equal "approve", result.outcome
  end

  test "payments outside the 45-day window do not count toward first-month rent" do
    lease = create_lease(start_date: Date.new(2025, 1, 1), monthly_rent: 1500)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "unpaid_rent", amount: 1500,
                     txn_date: Date.new(2025, 1, 5))
    create_line_item(claim: claim, category: "payment", amount: -1500,
                     txn_date: Date.new(2025, 4, 1))

    result = LineItemReview.new(claim).call

    assert_equal "decline", result.outcome
    assert_match(/first-month rent default/, result.reasons.first)
  end

  test "skips the first-month check when lease start or rent is missing" do
    lease = create_lease(start_date: nil, monthly_rent: nil)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "damage", amount: 400,
                     txn_date: Date.new(2025, 1, 5))

    assert_equal "approve", LineItemReview.new(claim).call.outcome
  end

  test "skips the first-month check when items have no transaction dates" do
    lease = create_lease(start_date: Date.new(2025, 1, 1), monthly_rent: 1500)
    claim = create_claim(lease: lease)
    create_line_item(claim: claim, category: "damage", amount: 400, txn_date: nil)

    assert_equal "approve", LineItemReview.new(claim).call.outcome
  end

  # -- stage 1 override ------------------------------------------------------------

  test "overwrites the stage 1 decision entirely" do
    claim = create_claim
    create_decision(claim: claim, outcome: "decline", amount: nil, reason: "no claim amount")
    create_line_item(claim: claim, category: "damage", amount: 500)

    LineItemReview.new(claim).call

    decision = claim.reload.adjudication_decision
    assert_equal "approve", decision.outcome
    assert_equal 500, decision.amount
    assert_equal 1, AdjudicationDecision.where(claim: claim).count
  end
end
