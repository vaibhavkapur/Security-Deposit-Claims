# Runs the rules engines over every claim that has no decision yet, so
# adjudication_decisions is fully populated up front and the UI only reads.
# Safe to re-run: claims that already have a decision are skipped.
class AdjudicationBatch
  def self.call
    done = 0
    Claim.where.missing(:adjudication_decision)
         .includes(:policy, :lease, :claim_line_items, :claim_activities)
         .find_each do |claim|
      EligibilityEngine.new(claim).call
      LineItemReview.new(claim).call if claim.claim_line_items.any?
      done += 1
    end
    done
  end
end
