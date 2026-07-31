require "test_helper"

# Validations and scopes for the small supporting models.
class MiscModelsTest < ActiveSupport::TestCase
  # -- AdjudicationDecision ----------------------------------------------------

  test "adjudication decision outcome must be approve or decline" do
    claim = create_claim
    decision = AdjudicationDecision.new(claim: claim, outcome: "maybe", reason: "r")
    refute decision.valid?
    assert_includes decision.errors[:outcome], "is not included in the list"

    decision.outcome = "approve"
    assert decision.valid?
  end

  test "adjudication decision requires a reason" do
    decision = AdjudicationDecision.new(claim: create_claim, outcome: "approve")
    refute decision.valid?
    assert_includes decision.errors[:reason], "can't be blank"
  end

  # -- ClaimLineItem -------------------------------------------------------------

  test "line item disposition must be allowed or denied" do
    claim = create_claim
    item = ClaimLineItem.new(claim: claim, document: create_document(claim: claim),
                             category: "damage", description: "x", amount: 1,
                             disposition: "parked")
    refute item.valid?
    assert_includes item.errors[:disposition], "is not included in the list"
  end

  test "line item defaults to denied awaiting adjudication" do
    item = create_line_item(claim: create_claim)
    assert_equal "denied", item.disposition
    assert_match(/awaiting adjudication/, item.disposition_reason)
  end

  # -- ClaimActivity ----------------------------------------------------------------

  test "claim activity requires author, body and timestamp but not a claim" do
    activity = ClaimActivity.new
    refute activity.valid?
    %i[author body occurred_at].each do |attr|
      assert_includes activity.errors[attr], "can't be blank", attr.to_s
    end

    activity.assign_attributes(author: "a", body: "b", occurred_at: Time.current, claim: nil)
    assert activity.valid?
  end

  test "claim activity scopes" do
    claim = create_claim
    linked = create_activity(claim: claim)
    orphan = create_activity(claim: nil, occurred_at: Time.zone.local(2025, 1, 1))
    later = create_activity(claim: nil, occurred_at: Time.zone.local(2025, 3, 1))

    assert_equal [orphan, later], ClaimActivity.unlinked.order(:id).to_a
    # linked occurred 2025-06-15, after both unlinked activities
    assert_equal [orphan, later, linked],
                 ClaimActivity.where(id: [linked, orphan, later]).chronological.to_a
  end

  # -- Property ------------------------------------------------------------------------

  test "property requires a street address and builds a full address" do
    refute Property.new.valid?
    property = create_property(street_address: "1 Elm St", city: "Waco", state: "TX", zip: nil)
    assert_equal "1 Elm St, Waco, TX", property.full_address
  end

  # -- Tenant ---------------------------------------------------------------------------

  test "tenant number must be 1 through 3 and unique per lease" do
    lease = create_lease
    Tenant.create!(lease: lease, tenant_number: 1)

    duplicate = Tenant.new(lease: lease, tenant_number: 1)
    refute duplicate.valid?

    out_of_range = Tenant.new(lease: lease, tenant_number: 4)
    refute out_of_range.valid?

    other_lease_ok = Tenant.new(lease: create_lease, tenant_number: 1)
    assert other_lease_ok.valid?
  end

  # -- Policy / PmCompany / CollectionRecord -----------------------------------------------

  test "policy number must be present and unique" do
    create_policy(policy_number: "P-1")
    refute Policy.new(policy_number: "P-1").valid?
    refute Policy.new.valid?
  end

  test "pm company name must be present and unique" do
    PmCompany.create!(name: "Acme")
    refute PmCompany.new(name: "Acme").valid?
    refute PmCompany.new.valid?
  end

  test "a claim can only have one collection record" do
    claim = create_claim
    CollectionRecord.create!(claim: claim)
    refute CollectionRecord.new(claim: claim).valid?
  end

  test "destroying a policy nullifies its claims" do
    policy = create_policy
    claim = create_claim(policy: policy)
    policy.destroy!
    assert_nil claim.reload.policy_id
  end
end
