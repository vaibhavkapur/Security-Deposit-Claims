namespace :adjudicate do
  desc "Replay all claims through the rules engine and compare with historical outcomes"
  task replay: :environment do
    AdjudicationDecision.delete_all

    puts "Replaying #{Claim.count} claims through both stages..."
    AdjudicationBatch.call

    final = AdjudicationDecision.all.index_by(&:claim_id)

    # Compare with history
    historical_declined = Claim.where(status: "Declined").pluck(:id).to_set
    historical_paid = Claim.where(status: %w[Posted Approved]).pluck(:id).to_set

    engine_declined = final.select { |_, d| d.outcome == "decline" }.keys.to_set
    engine_approved = final.select { |_, d| d.outcome == "approve" }.keys.to_set

    puts "\nEngine outcomes: #{final.values.map(&:outcome).tally}"
    puts "\n--- vs history ---"
    puts "engine declines that history also declined: #{(engine_declined & historical_declined).size}/#{engine_declined.size}"
    puts "engine declines that history PAID (false declines): #{(engine_declined & historical_paid).size}"
    puts "historical declines the engine caught: #{(engine_declined & historical_declined).size}/#{historical_declined.size}"
    puts "historical declines the engine approved (misses): #{(engine_approved & historical_declined).size}"

    # Amount accuracy on approved claims history also paid
    matches = mism = 0
    engine_approved.each do |claim_id|
      d = final[claim_id]
      claim = Claim.find(claim_id)
      next unless historical_paid.include?(claim_id) && claim.approved_benefit_amount && d.amount
      (claim.approved_benefit_amount - d.amount).abs < 0.01 ? matches += 1 : mism += 1
    end
    puts "\napproved amount vs history: #{matches} exact, #{mism} differ"
  end
end
