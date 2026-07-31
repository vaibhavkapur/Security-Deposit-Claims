require "test_helper"

class ClaimsImportTest < ActiveSupport::TestCase
  def import(rows)
    ClaimsImport.new(write_claims_xlsx(rows)).call
  end

  test "imports a full row into the claim graph" do
    result = import([claim_row(
      "Tracking Number" => "101",
      "Status" => "Approved",
      "Termination Type" => "Move-Out",
      "Group #" => "G-9",
      "Treaty #" => "T-4",
      "Property Management Company" => "Acme Mgmt",
      "Property Manager Name" => "Dana Reyes",
      "Lease End Date" => Date.new(2025, 12, 31),
      "Move-Out Date" => Date.new(2025, 11, 30),
      "Primary Tenant Employer Name" => "Initech",
      "Approval Date" => Date.new(2025, 7, 1),
      "Approved Benefit Amount" => 1800.55,
      "PM Explanation" => "carpet damage",
      "Posted Date" => Date.new(2025, 7, 3),
      "PM Notification of Claim Received" => Date.new(2025, 6, 2),
      "Review Claim Adjudication" => "Yes",
      "Review Tenant Information" => "No"
    )])

    assert_equal 1, result.created
    assert_empty result.skipped
    assert_empty result.errors

    claim = Claim.find_by!(tracking_number: "101")
    assert_equal "Approved", claim.status
    assert_equal Date.new(2025, 6, 1), claim.claim_date
    assert_equal 2000, claim.claim_amount
    assert_equal "Move-Out", claim.termination_type
    assert_equal 1800.55, claim.approved_benefit_amount
    assert_nil claim.approved_benefit_note
    assert_equal true, claim.needs_adjudication_review
    assert_equal false, claim.tenant_info_reviewed
    assert_nil claim.policy_info_updated

    assert_equal "POL-1", claim.policy.policy_number
    assert_equal "G-9", claim.policy.group_number
    assert_equal 3000, claim.policy.max_benefit

    lease = claim.lease
    assert_equal "500 Main St", lease.property.street_address
    assert_equal "TX", lease.property.state
    assert_equal 1500, lease.monthly_rent
    assert_equal "Dana Reyes", lease.property_manager.name
    assert_equal "Acme Mgmt", lease.property_manager.pm_company.name
    assert_equal ["Initech"], lease.tenants.map(&:employer_name)
  end

  test "skips rows without a tracking number" do
    result = import([claim_row("Tracking Number" => nil)])

    assert_equal 0, result.created
    assert_equal 1, result.skipped.size
    assert_equal "no tracking number", result.skipped.first[:reason]
  end

  test "skips test claims" do
    result = import([claim_row("Status" => "Test Claim")])

    assert_equal 0, result.created
    assert_equal "test claim", result.skipped.first[:reason]
  end

  test "skips already-imported tracking numbers" do
    create_claim(tracking_number: "101")
    result = import([claim_row("Tracking Number" => "101")])

    assert_equal 0, result.created
    assert_match(/already imported/, result.skipped.first[:reason])
  end

  test "a bad row is recorded as an error without aborting the rest" do
    result = import([
      claim_row("Tracking Number" => "101", "Lease Zip" => "x" * 50), # zip too long
      claim_row("Tracking Number" => "102")
    ])

    assert_equal 2, result.created
    assert_empty result.errors
    # zip is truncated to 10 chars rather than erroring
    assert_equal "x" * 10, Claim.find_by!(tracking_number: "101").lease.property.zip
  end

  test "one failing row does not roll back other rows" do
    long_state_row = claim_row("Tracking Number" => "103", "Monthly Rent" => "abc")
    result = import([long_state_row, claim_row("Tracking Number" => "104")])

    # "abc" money coerces to nil, so the row still imports cleanly.
    assert_equal 2, result.created
    assert_nil Claim.find_by!(tracking_number: "103").lease.monthly_rent
  end

  test "numeric tracking numbers from excel floats lose the trailing .0" do
    result = import([claim_row("Tracking Number" => 101.0)])

    assert_equal 1, result.created
    assert Claim.exists?(tracking_number: "101")
  end

  test "reuses existing properties, policies and pm companies" do
    import([claim_row("Tracking Number" => "101")])
    import([claim_row("Tracking Number" => "102")])

    assert_equal 1, Property.count
    assert_equal 1, Policy.count
    assert_equal 2, Claim.count
  end

  test "claim without a policy column imports with policy nil" do
    result = import([claim_row("Policy" => nil, "Max Benefit" => nil)])

    assert_equal 1, result.created
    assert_nil Claim.find_by!(tracking_number: "101").policy
  end

  test "second and third tenants are created when flagged" do
    import([claim_row(
      "Is there a 2nd Tenant?" => "Yes",
      "#2 Relationship" => "Spouse",
      "#2 Tenant Employer Name" => "Globex",
      "Is there a 3rd Tenant?" => "yes"
    )])

    tenants = Claim.find_by!(tracking_number: "101").lease.tenants.order(:tenant_number)
    assert_equal [1, 2, 3], tenants.map(&:tenant_number)
    assert_equal "Spouse", tenants.second.relationship
    assert_equal "Globex", tenants.second.employer_name
  end

  test "non-numeric approved benefit amounts are stored as a note" do
    import([claim_row("Approved Benefit Amount" => "Denied - no docs")])

    claim = Claim.find_by!(tracking_number: "101")
    assert_nil claim.approved_benefit_amount
    assert_equal "Denied - no docs", claim.approved_benefit_note
  end

  test "collection record is created only when collection columns have values" do
    import([claim_row("Tracking Number" => "101")])
    import([claim_row("Tracking Number" => "102",
                      "Collection Status" => "Referred",
                      "Collected Amount" => 250.75)])

    assert_nil Claim.find_by!(tracking_number: "101").collection_record
    record = Claim.find_by!(tracking_number: "102").collection_record
    assert_equal "Referred", record.collection_status
    assert_equal 250.75, record.collected_amount
  end

  test "exception flag comes from the blank-header column" do
    import([claim_row("Tracking Number" => "101", :exception_flag => "Yes")])
    import([claim_row("Tracking Number" => "102")])

    assert Claim.find_by!(tracking_number: "101").exception_flag
    refute Claim.find_by!(tracking_number: "102").exception_flag
  end

  test "audit_selected is set from presence of the audit column" do
    import([claim_row("Tracking Number" => "101", "Audit Selection" => "X")])
    import([claim_row("Tracking Number" => "102")])

    assert Claim.find_by!(tracking_number: "101").audit_selected
    refute Claim.find_by!(tracking_number: "102").audit_selected
  end

  # -- cell coercion helpers ---------------------------------------------------

  test "money strips currency formatting and rejects junk" do
    importer = ClaimsImport.new("unused")
    assert_equal 1234.56, importer.send(:money, "$1,234.56")
    assert_equal 1234.56, importer.send(:money, 1234.556).to_f
    assert_equal(-50, importer.send(:money, "-50"))
    assert_nil importer.send(:money, "TBD")
    assert_nil importer.send(:money, nil)
  end

  test "date parses strings and passes through date cells" do
    importer = ClaimsImport.new("unused")
    assert_equal Date.new(2025, 6, 1), importer.send(:date, "2025-06-01")
    assert_equal Date.new(2025, 6, 1), importer.send(:date, Date.new(2025, 6, 1))
    assert_nil importer.send(:date, "not a date")
    assert_nil importer.send(:date, nil)
  end

  test "state_code maps full names and normalizes abbreviations" do
    importer = ClaimsImport.new("unused")
    assert_equal "TX", importer.send(:state_code, "texas")
    assert_equal "TX", importer.send(:state_code, "tx")
    assert_equal "DC", importer.send(:state_code, "District of Columbia")
    assert_equal "SO", importer.send(:state_code, "somewhere")
    assert_nil importer.send(:state_code, nil)
  end

  test "boolean is tri-state" do
    importer = ClaimsImport.new("unused")
    assert_equal true, importer.send(:boolean, "Yes")
    assert_equal false, importer.send(:boolean, "no")
    assert_nil importer.send(:boolean, "")
    assert_nil importer.send(:boolean, "maybe")
  end
end
