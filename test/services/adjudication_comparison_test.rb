require "test_helper"

class AdjudicationComparisonTest < ActiveSupport::TestCase
  def decided_claim(status:, sheet_amount: nil, my_outcome: "approve", my_amount: nil, my_reason: "r")
    claim = create_claim(status: status, approved_benefit_amount: sheet_amount)
    create_decision(claim: claim, outcome: my_outcome, amount: my_amount, reason: my_reason)
    claim
  end

  test "only claims with decisions become rows" do
    decided_claim(status: "Approved")
    create_claim(status: "Approved") # no decision

    result = AdjudicationComparison.new.call
    assert_equal 1, result.rows.size
  end

  # -- sheet outcome mapping ---------------------------------------------------

  test "maps Approved, Approved Revised and Posted to approve" do
    ["Approved", "Approved Revised", "Posted"].each do |status|
      claim = decided_claim(status: status)
      row = AdjudicationComparison.new.call.rows.find { |r| r.claim == claim }
      assert_equal "approve", row.sheet_outcome, "status #{status}"
    end
  end

  test "maps Declined to decline and everything else to open" do
    declined = decided_claim(status: "Declined")
    hold = decided_claim(status: "HOLD")
    blank = decided_claim(status: nil)

    result = AdjudicationComparison.new.call
    rows = result.rows.index_by(&:claim)
    assert_equal "decline", rows[declined].sheet_outcome
    assert_equal "open", rows[hold].sheet_outcome
    assert_equal "open", rows[blank].sheet_outcome
  end

  test "open rows are excluded from the decided set and the matrix" do
    decided_claim(status: "Approved")
    decided_claim(status: "In Process")

    result = AdjudicationComparison.new.call
    assert_equal 1, result.decided_rows.size
    assert_equal 1, result.open_rows.size
    assert_equal 1, result.matrix.values.sum
  end

  # -- matrix and counts ---------------------------------------------------------

  test "builds the agreement matrix over decided rows" do
    decided_claim(status: "Approved", my_outcome: "approve")
    decided_claim(status: "Approved", my_outcome: "decline")
    decided_claim(status: "Declined", my_outcome: "decline")
    decided_claim(status: "Declined", my_outcome: "approve")
    decided_claim(status: "Declined", my_outcome: "decline")

    result = AdjudicationComparison.new.call

    assert_equal 1, result.matrix[%w[approve approve]]
    assert_equal 1, result.matrix[%w[decline approve]]
    assert_equal 2, result.matrix[%w[decline decline]]
    assert_equal 1, result.matrix[%w[approve decline]]
    assert_equal 3, result.agreement_count
    assert_equal 2, result.my_approve_count
    assert_equal 3, result.my_decline_count
    assert_equal 2, result.sheet_approve_count
    assert_equal 3, result.sheet_decline_count
  end

  test "splits mismatches by whether the claim has extracted line items" do
    decided_claim(status: "Approved", my_outcome: "approve") # agreement — excluded
    with_pdf = decided_claim(status: "Approved", my_outcome: "decline")
    create_line_item(claim: with_pdf)
    without_pdf = decided_claim(status: "Declined", my_outcome: "approve")

    result = AdjudicationComparison.new.call

    assert_equal [with_pdf, without_pdf].to_set, result.mismatch_rows.map(&:claim).to_set
    assert_equal [without_pdf], result.missing_pdf_mismatch_rows.map(&:claim)
  end

  # -- amount comparison ------------------------------------------------------------

  test "computes amount deltas for rows both sides approved and priced" do
    exact = decided_claim(status: "Approved", sheet_amount: 1000, my_amount: 1000)
    higher = decided_claim(status: "Approved", sheet_amount: 500, my_amount: 800)
    lower = decided_claim(status: "Approved", sheet_amount: 900, my_amount: 600)
    decided_claim(status: "Approved", sheet_amount: nil, my_amount: 700) # unpriced

    result = AdjudicationComparison.new.call

    assert_equal 4, result.both_approved_rows.size
    assert_equal 3, result.priced_rows.size
    assert_equal 1, result.unpriced_count
    assert_equal [exact], result.exact_rows.map(&:claim)
    assert_equal [higher], result.higher_rows.map(&:claim)
    assert_equal [lower], result.lower_rows.map(&:claim)
    assert_equal 2400, result.my_total
    assert_equal 2400, result.sheet_total
  end

  test "amount_delta is nil unless both amounts are present" do
    row = AdjudicationComparison::Row.new(my_amount: nil, sheet_amount: 100)
    assert_nil row.amount_delta
    row2 = AdjudicationComparison::Row.new(my_amount: 100, sheet_amount: 40)
    assert_equal 60, row2.amount_delta
  end

  # -- reason categorization ----------------------------------------------------------

  test "categorizes decision reasons by their first segment" do
    {
      "eviction: historically paid full max benefit (87% exact)" =>
        "Eviction — paid at full max benefit",
      "ledger shows a recoverable balance (allowed charges exceed credits)" =>
        "Ledger shows a recoverable balance (Stage 2)",
      "no recoverable balance in ledger (credits cover all allowed charges)" =>
        "Ledger shows no recoverable balance (Stage 2)",
      "claim amount 5000.0 capped at policy max benefit 3000.0" =>
        "Claim amount capped at max benefit",
      "claim amount 1000.0 within policy max benefit 3000.0" =>
        "Claim amount paid as filed (within max benefit)",
      "no claim amount" => "No claim amount on the spreadsheet row",
      "no policy on file" => "No policy on file",
      "policy has no max benefit" => "Policy has no max benefit",
      "open hold reason: waiting" => "Open hold reason on the row",
      "possible first-month rent default: ledger covers move-in" =>
        "Comment flag: possible first-month rent default",
      %(comments flag — tenant dispute: "disputing") => "Comment flag: tenant dispute",
      %(comments flag — explicit do-not-pay instruction: "do not pay") =>
        "Comment flag: do-not-pay instruction",
      "claim filed before lease start (data error?)" => "Claim filed before lease start",
      "claim amount is not positive" => "Claim amount not positive",
      "something unrecognized" => "Other"
    }.each do |reason, expected|
      claim = decided_claim(status: "Approved", my_reason: reason)
      row = AdjudicationComparison.new.call.rows.find { |r| r.claim == claim }
      assert_equal expected, row.my_category, "reason: #{reason}"
      claim.adjudication_decision.destroy!
    end
  end

  test "categorization uses only the first segment of a multi-part reason" do
    claim = decided_claim(status: "Approved",
                          my_reason: "no policy on file; no claim amount")
    row = AdjudicationComparison.new.call.rows.find { |r| r.claim == claim }
    assert_equal "No policy on file", row.my_category
  end

  test "groups amount differences by category, largest group first" do
    2.times { decided_claim(status: "Approved", sheet_amount: 100, my_amount: 200, my_reason: "no claim amount") }
    decided_claim(status: "Approved", sheet_amount: 100, my_amount: 300,
                  my_reason: "eviction: historically paid full max benefit")
    decided_claim(status: "Approved", sheet_amount: 100, my_amount: 100, my_reason: "no claim amount") # exact — excluded

    groups = AdjudicationComparison.new.call.amount_diff_groups
    assert_equal ["No claim amount on the spreadsheet row",
                  "Eviction — paid at full max benefit"], groups.keys
    assert_equal [2, 1], groups.values.map(&:size)
  end
end
