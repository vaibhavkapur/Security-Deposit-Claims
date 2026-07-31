# Scans a claim's linked comment threads (claim_activities) for language that
# signals the claim shouldn't be paid as-is: explicit do-not-pay instructions,
# active tenant disputes, attorney/legal involvement, or suspected fraud.
# Under the binary conservative policy any hit declines the claim — both
# EligibilityEngine (Stage 1) and LineItemReview (Stage 2) check these, so a
# flag survives the Stage 2 overwrite.
class CommentRedFlags
  PATTERNS = {
    "explicit do-not-pay instruction" => /do\s*not\s+pay|don'?t\s+pay/i,
    "tenant dispute" => /disput/i,
    "attorney or legal action" => /attorney|lawyer|lawsuit|litigat|legal\s+(action|claim)/i,
    "possible fraud or forgery" => /fraud|forger|forged|falsif/i
  }.freeze

  def self.for(claim)
    activities = claim.claim_activities
    PATTERNS.filter_map do |label, pattern|
      hit = activities.find { |activity| activity.body.match?(pattern) }
      next unless hit

      %(comments flag — #{label}: "#{hit.body.strip.truncate(90)}")
    end
  end
end
