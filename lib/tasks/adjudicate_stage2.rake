namespace :adjudicate do
  desc "Run Stage 2 (line-item review) on claims with extracted line items; compare with history"
  task stage2: :environment do
    claim_ids = ClaimLineItem.distinct.pluck(:claim_id)
    abort "No claims have extracted line items yet — run extraction:run first." if claim_ids.empty?

    puts "Running Stage 2 on #{claim_ids.size} claims with line items..."
    exact = close = differ = declined = 0
    Claim.where(id: claim_ids).includes(:policy, :lease, :claim_line_items).find_each do |claim|
      result = LineItemReview.new(claim).call
      next if result.nil?

      if result.outcome == "decline"
        declined += 1
      elsif claim.approved_benefit_amount && result.amount
        diff = (claim.approved_benefit_amount - result.amount).abs
        if diff < 0.01 then exact += 1
        elsif diff <= claim.approved_benefit_amount * 0.1 then close += 1
        else differ += 1
        end
      end
    end

    puts "auto-decided vs history: #{exact} exact, #{close} within 10%, #{differ} differ; #{declined} declined"
  end
end
