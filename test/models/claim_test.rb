require "test_helper"

class ClaimTest < ActiveSupport::TestCase
  test "requires a tracking number" do
    claim = Claim.new(lease: create_lease)
    refute claim.valid?
    assert_includes claim.errors[:tracking_number], "can't be blank"
  end

  test "tracking number must be unique" do
    create_claim(tracking_number: "900")
    duplicate = Claim.new(lease: create_lease, tracking_number: "900")
    refute duplicate.valid?
    assert_includes duplicate.errors[:tracking_number], "has already been taken"
  end

  test "requires a lease but not a policy" do
    claim = Claim.new(tracking_number: "901", policy: nil)
    refute claim.valid?
    assert_includes claim.errors[:lease], "must exist"

    claim.lease = create_lease
    assert claim.valid?
  end

  test "destroying a claim removes its dependent records" do
    claim = create_claim
    create_activity(claim: claim)
    create_line_item(claim: claim)
    create_decision(claim: claim)
    CollectionRecord.create!(claim: claim)

    claim.destroy!

    assert_empty ClaimActivity.where(claim_id: claim.id)
    assert_empty ClaimLineItem.where(claim_id: claim.id)
    assert_empty Document.where(claim_id: claim.id)
    assert_empty AdjudicationDecision.where(claim_id: claim.id)
    assert_empty CollectionRecord.where(claim_id: claim.id)
  end
end
