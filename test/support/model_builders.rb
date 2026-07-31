# Builder helpers for constructing valid model graphs in tests without
# fixtures. Every builder fills in the minimum valid attributes and accepts
# overrides, so tests only state what they care about.
module ModelBuilders
  def create_property(**attrs)
    Property.create!({
      street_address: "#{unique_number} Test St",
      city: "Austin", state: "TX", zip: "78701"
    }.merge(attrs))
  end

  def create_lease(**attrs)
    attrs[:property] ||= create_property
    Lease.create!({
      start_date: Date.new(2025, 1, 1),
      end_date: Date.new(2025, 12, 31),
      monthly_rent: 1500
    }.merge(attrs))
  end

  def create_policy(**attrs)
    Policy.create!({
      policy_number: "POL-#{unique_number}",
      max_benefit: 3000
    }.merge(attrs))
  end

  # Claim with a lease and (by default) a policy attached. Pass policy: nil
  # explicitly to build a claim without one.
  def create_claim(**attrs)
    attrs[:lease] ||= create_lease
    attrs = { policy: create_policy }.merge(attrs)
    Claim.create!({
      tracking_number: unique_number.to_s,
      claim_date: Date.new(2025, 6, 1),
      claim_amount: 2000,
      status: "New"
    }.merge(attrs))
  end

  def create_document(claim:, **attrs)
    Document.create!({
      claim: claim,
      original_name: "ledger.pdf",
      relative_path: "docs/#{claim.tracking_number}/ledger.pdf",
      content_hash: SecureRandom.hex(32),
      mime_type: "application/pdf",
      byte_size: 1024,
      doc_type: "ledger",
      storage_key: "ab/#{SecureRandom.hex(32)}.pdf"
    }.merge(attrs))
  end

  def create_line_item(claim:, **attrs)
    attrs[:document] ||= (@_line_item_docs ||= {})[claim.id] ||= create_document(claim: claim)
    ClaimLineItem.create!({
      claim: claim,
      category: "damage",
      description: "wall repair",
      amount: 100
    }.merge(attrs))
  end

  def create_activity(claim:, **attrs)
    ClaimActivity.create!({
      claim: claim,
      author: "adjuster",
      body: "routine note",
      occurred_at: Time.zone.local(2025, 6, 15, 12, 0)
    }.merge(attrs))
  end

  def create_decision(claim:, **attrs)
    AdjudicationDecision.create!({
      claim: claim,
      outcome: "approve",
      amount: 100,
      reason: "test decision"
    }.merge(attrs))
  end

  @counter = 0
  @counter_mutex = Mutex.new

  def self.next_number
    @counter_mutex.synchronize { @counter += 1 }
  end

  def unique_number
    ModelBuilders.next_number
  end
end
