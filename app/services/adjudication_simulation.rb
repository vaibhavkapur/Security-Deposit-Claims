# What-if analysis for the analytics page: re-runs my adjudication decisions
# over the spreadsheet-decided claims with individual rules changed, and
# measures how close each variant gets to the spreadsheet's outcomes and
# amounts. Read-only; nothing is persisted.
#
# Decline gates are recovered from the stored decision reason (the engines
# write one "; "-joined segment per gate), so a variant can selectively
# override a gate without re-running the engines.
class AdjudicationSimulation
  GATE_PATTERNS = {
    no_policy: /\Ano policy on file/,
    no_max: /\Apolicy has no max benefit/,
    no_amount: /\Ano claim amount/,
    nonpositive: /\Aclaim amount is not positive/,
    pre_lease: /\Aclaim filed before lease start/,
    hold: /\Aopen hold reason/,
    flag: /\A(possible first-month rent default|comments flag)/,
    ledger_zero: /\Ano recoverable balance/
  }.freeze

  # Cumulative variants: each row keeps the previous row's toggles.
  SCENARIOS = [
    ["Current rules", []],
    ["+ missing claim amount is paid at max benefit", [:ledger_fallback, :pay_missing_at_max]],
    ["+ every approval priced at max benefit", [:ledger_fallback, :pay_missing_at_max, :ignore_flags_holds, :misc_gates, :max_for_all]]
  ].freeze

  Facts = Struct.new(:gates, :base_outcome, :base_amount, :payout, :allpos_payout,
                     :claim_amount, :max_benefit, :eviction, :blank_term,
                     :termination_type, :has_items,
                     :sheet_outcome, :sheet_amount, keyword_init: true)

  Scenario = Struct.new(:name, :approval_rate, :agreement_rate, :both_approved,
                        :exact_pct, :my_total, :mae, keyword_init: true)

  Result = Struct.new(:scenarios, :oracle, keyword_init: true)

  def call
    facts = build_facts
    Result.new(
      scenarios: SCENARIOS.map { |name, toggles| run_scenario(name, toggles, facts) },
      oracle: oracle_ceiling(facts)
    )
  end

  private

  def build_facts
    Claim.includes(:policy, :adjudication_decision, :claim_line_items).filter_map do |c|
      d = c.adjudication_decision
      next unless d
      sheet =
        if AdjudicationComparison::SHEET_APPROVE.include?(c.status) then "approve"
        elsif AdjudicationComparison::SHEET_DECLINE.include?(c.status) then "decline"
        end
      next unless sheet

      items = c.claim_line_items
      cap = c.policy&.max_benefit
      payout = allpos = nil
      if items.any?
        credits = items.select { |i| i.amount.negative? && i.category.in?(%w[credit payment]) }.sum(&:amount)
        net = items.select { |i| i.disposition == "allowed" && i.amount.positive? }.sum(&:amount) + credits
        net_all = items.select { |i| i.amount.positive? }.sum(&:amount) + credits
        payout = cap ? [net, cap].min : net
        allpos = cap ? [net_all, cap].min : net_all
      end

      Facts.new(
        gates: d.outcome == "decline" ? gates_for(d.reason) : [],
        base_outcome: d.outcome, base_amount: d.amount,
        payout: payout, allpos_payout: allpos,
        claim_amount: c.claim_amount, max_benefit: cap,
        eviction: c.termination_type == "Eviction",
        blank_term: c.termination_type.blank?,
        termination_type: c.termination_type,
        has_items: items.any?,
        sheet_outcome: sheet, sheet_amount: c.approved_benefit_amount
      )
    end
  end

  def gates_for(reason)
    reason.split("; ").filter_map { |seg| GATE_PATTERNS.find { |_, p| seg.match?(p) }&.first }.uniq
  end

  def decide(f, toggles)
    overridable = []
    overridable << :ledger_zero if toggles.include?(:ledger_fallback)
    overridable << :no_amount if toggles.include?(:pay_missing_at_max)
    overridable.push(:hold, :flag) if toggles.include?(:ignore_flags_holds)
    overridable.push(:pre_lease, :no_max) if toggles.include?(:misc_gates)
    return ["decline", nil] if (f.gates - overridable).any?

    stage2 = f.payout&.positive? && !f.gates.include?(:ledger_zero)
    amount =
      if stage2 then f.payout
      elsif f.eviction && f.max_benefit then f.max_benefit
      elsif f.claim_amount && f.max_benefit then [f.claim_amount, f.max_benefit].min
      elsif f.max_benefit && toggles.include?(:pay_missing_at_max) then f.max_benefit
      else f.claim_amount
      end
    return ["decline", nil] if amount.nil?

    if f.max_benefit && (toggles.include?(:max_for_all) ||
        (toggles.include?(:max_for_all_stage1) && !stage2) ||
        (toggles.include?(:max_for_blank) && !stage2 && f.blank_term))
      amount = f.max_benefit
    end
    ["approve", amount]
  end

  def run_scenario(name, toggles, facts)
    approvals = agree = both = exact = priced = 0
    my_total = mae = 0.0
    facts.each do |f|
      outcome, amount = decide(f, toggles)
      approvals += 1 if outcome == "approve"
      agree += 1 if outcome == f.sheet_outcome
      next unless outcome == "approve" && f.sheet_outcome == "approve"
      both += 1
      next unless amount && f.sheet_amount
      priced += 1
      my_total += amount
      diff = (amount - f.sheet_amount).abs
      exact += 1 if diff.zero?
      mae += diff
    end
    Scenario.new(
      name: name,
      approval_rate: 100.0 * approvals / facts.size,
      agreement_rate: 100.0 * agree / facts.size,
      both_approved: both,
      exact_pct: priced.zero? ? 0 : 100.0 * exact / priced,
      my_total: my_total,
      mae: priced.zero? ? 0 : mae / priced
    )
  end

  def both_approved(facts)
    facts.select { |f| f.base_outcome == "approve" && f.sheet_outcome == "approve" && f.sheet_amount }
  end

  # Can the sheet amount be produced by ANY computable formula? The share that
  # can't bounds every rule-based matcher from above.
  def oracle_ceiling(facts)
    rows = both_approved(facts)
    unmatched = rows.reject do |f|
      candidates(f).any? { |v| v == f.sheet_amount }
    end
    { total: rows.size, matched: rows.size - unmatched.size,
      pct: 100.0 * (rows.size - unmatched.size) / rows.size,
      unmatched: unmatched.size,
      unmatched_without_items: unmatched.count { |f| !f.has_items } }
  end

  def candidates(f)
    list = [f.claim_amount, f.max_benefit, f.payout, f.allpos_payout].compact
    list << [f.claim_amount, f.max_benefit].min if f.claim_amount && f.max_benefit
    list
  end
end
