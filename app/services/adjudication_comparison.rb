# Claim-by-claim comparison of my adjudication_decisions against the outcome
# recorded in Claims.xlsx (claims.status + approved_benefit_amount).
#
# Spreadsheet statuses map to outcomes:
#   Approved / Approved Revised / Posted -> approve
#   Declined                             -> decline
#   anything else (HOLD, In Process, New, Pending Docs from PM) -> open
#
# Headline rates and the agreement matrix are computed over the claims the
# spreadsheet actually decided, so both sides are measured on the same set.
class AdjudicationComparison
  SHEET_APPROVE = ["Approved", "Approved Revised", "Posted"].freeze
  SHEET_DECLINE = ["Declined"].freeze

  Row = Struct.new(:claim, :my_outcome, :my_amount, :my_reason, :my_category,
                   :sheet_outcome, :sheet_amount, keyword_init: true) do
    def amount_delta
      return nil unless my_amount && sheet_amount
      my_amount - sheet_amount
    end
  end

  Result = Struct.new(
    :rows, :decided_rows, :open_rows,
    :my_approve_count, :my_decline_count,
    :sheet_approve_count, :sheet_decline_count,
    :matrix, :agreement_count,
    :both_approved_rows, :priced_rows, :unpriced_count,
    :exact_rows, :higher_rows, :lower_rows,
    :my_total, :sheet_total,
    :amount_diff_groups,
    keyword_init: true
  )

  # Matched against the first "; "-joined segment of the decision reason,
  # which EligibilityEngine / LineItemReview write in priority order.
  MY_REASON_CATEGORIES = [
    [/\Aeviction/, "Eviction — paid at full max benefit"],
    [/\Aledger shows a recoverable balance/, "Ledger shows a recoverable balance (Stage 2)"],
    [/\Ano recoverable balance in ledger/, "Ledger shows no recoverable balance (Stage 2)"],
    [/\Aclaim amount .* capped at/, "Claim amount capped at max benefit"],
    [/\Aclaim amount .* within/, "Claim amount paid as filed (within max benefit)"],
    [/\Ano claim amount/, "No claim amount on the spreadsheet row"],
    [/\Ano policy on file/, "No policy on file"],
    [/\Apolicy has no max benefit/, "Policy has no max benefit"],
    [/\Aopen hold reason/, "Open hold reason on the row"],
    [/first-month rent default/, "Comment flag: possible first-month rent default"],
    [/tenant dispute/, "Comment flag: tenant dispute"],
    [/do-not-pay/, "Comment flag: do-not-pay instruction"],
    [/\Aclaim filed before lease start/, "Claim filed before lease start"],
    [/\Aclaim amount is not positive/, "Claim amount not positive"]
  ].freeze

  def call
    rows = build_rows
    decided = rows.select { |r| r.sheet_outcome != "open" }
    open_rows = rows - decided

    matrix = Hash.new(0)
    decided.each { |r| matrix[[r.my_outcome, r.sheet_outcome]] += 1 }

    both_approved = decided.select { |r| r.my_outcome == "approve" && r.sheet_outcome == "approve" }
    priced = both_approved.select { |r| r.amount_delta }

    Result.new(
      rows: rows,
      decided_rows: decided,
      open_rows: open_rows,
      my_approve_count: decided.count { |r| r.my_outcome == "approve" },
      my_decline_count: decided.count { |r| r.my_outcome == "decline" },
      sheet_approve_count: decided.count { |r| r.sheet_outcome == "approve" },
      sheet_decline_count: decided.count { |r| r.sheet_outcome == "decline" },
      matrix: matrix,
      agreement_count: matrix[%w[approve approve]] + matrix[%w[decline decline]],
      both_approved_rows: both_approved,
      priced_rows: priced,
      unpriced_count: both_approved.size - priced.size,
      exact_rows: priced.select { |r| r.amount_delta.zero? },
      higher_rows: priced.select { |r| r.amount_delta.positive? },
      lower_rows: priced.select { |r| r.amount_delta.negative? },
      my_total: priced.sum(&:my_amount),
      sheet_total: priced.sum(&:sheet_amount),
      amount_diff_groups: group_by_size(priced.reject { |r| r.amount_delta.zero? }, &:my_category)
    )
  end

  private

  def build_rows
    Claim.joins(:adjudication_decision).includes(:adjudication_decision).map do |claim|
      decision = claim.adjudication_decision
      Row.new(
        claim: claim,
        my_outcome: decision.outcome,
        my_amount: decision.amount,
        my_reason: decision.reason,
        my_category: categorize_my_reason(decision.reason),
        sheet_outcome: sheet_outcome(claim.status),
        sheet_amount: claim.approved_benefit_amount
      )
    end
  end

  def sheet_outcome(status)
    return "approve" if SHEET_APPROVE.include?(status)
    return "decline" if SHEET_DECLINE.include?(status)
    "open"
  end

  def categorize_my_reason(reason)
    primary = reason.to_s.split("; ").first.to_s
    MY_REASON_CATEGORIES.each do |pattern, label|
      return label if primary.match?(pattern)
    end
    "Other"
  end

  # {label => rows}, largest group first
  def group_by_size(rows, &key)
    rows.group_by(&key).sort_by { |_, group| -group.size }.to_h
  end
end
