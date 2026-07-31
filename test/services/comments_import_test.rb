require "test_helper"

class CommentsImportTest < ActiveSupport::TestCase
  setup do
    @empty_docs_dir = Dir.mktmpdir("docs")
  end

  def import(comments)
    path = write_claims_xlsx([], comments: comments)
    CommentsImport.new(path, docs_dir: @empty_docs_dir).call
  end

  test "returns zeros when the workbook has no Comments sheet" do
    path = write_claims_xlsx([])
    result = CommentsImport.new(path, docs_dir: @empty_docs_dir).call

    assert_equal 0, result.imported
    assert_equal 0, result.linked_threads
    assert_equal 0, ClaimActivity.count
  end

  test "imports comments with author, body, timestamp and row ref" do
    import([["Row 5", "called the PM", "jsmith", "06/15/25 02:30 PM"]])

    activity = ClaimActivity.sole
    assert_equal "called the PM", activity.body
    assert_equal "jsmith", activity.author
    assert_equal "Row 5", activity.source_row_ref
    assert_equal DateTime.new(2025, 6, 15, 14, 30), activity.occurred_at
  end

  test "skips rows with blank bodies or unparseable timestamps" do
    result = import([
      ["Row 1", "", "jsmith", "06/15/25 02:30 PM"],
      ["Row 2", "no timestamp", "jsmith", "yesterday"],
      ["Row 3", "good", "jsmith", "06/15/25 02:30 PM"]
    ])

    assert_equal 1, result.imported
    assert_equal "good", ClaimActivity.sole.body
  end

  test "defaults missing authors to unknown" do
    import([["Row 5", "note", nil, "06/15/25 02:30 PM"]])
    assert_equal "unknown", ClaimActivity.sole.author
  end

  test "keeps threads with non-standard refs unlinked but imported" do
    result = import([["oddball", "note", "j", "06/15/25 02:30 PM"]])

    assert_equal 1, result.imported
    activity = ClaimActivity.sole
    assert_nil activity.claim_id
    assert_nil activity.source_row_ref
  end

  # -- explicit_ref linking ------------------------------------------------------

  test "links a thread that cites a tracking number" do
    claim = create_claim(tracking_number: "546")

    import([["Row 9", "approved claim #546 today", "j", "06/15/25 02:30 PM"]])

    activity = ClaimActivity.sole
    assert_equal claim.id, activity.claim_id
    assert_equal "explicit_ref", activity.link_method
  end

  test "ignores refs preceded by stopword context like unit or phone" do
    create_claim(tracking_number: "546")

    import([["Row 9", "tenant lives in unit #546", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.sole.claim_id
  end

  test "ignores small numbers like tenant ordinals" do
    create_claim(tracking_number: "2")

    import([["Row 9", "spoke to #2 tenant about this", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.sole.claim_id
  end

  test "does not link when two different tracking numbers are cited" do
    create_claim(tracking_number: "546")
    create_claim(tracking_number: "547")

    import([["Row 9", "could be #546 or #547", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.sole.claim_id
  end

  # -- address linking -------------------------------------------------------------

  test "links a thread mentioning a street address unique to one claim" do
    property = create_property(street_address: "10205 Maydelle Ave")
    claim = create_claim(lease: create_lease(property: property))

    import([["Row 3", "Inspection done at 10205 Maydelle yesterday", "j", "06/15/25 02:30 PM"]])

    activity = ClaimActivity.sole
    assert_equal claim.id, activity.claim_id
    assert_equal "address", activity.link_method
  end

  test "does not link addresses shared by multiple claims" do
    property = create_property(street_address: "10205 Maydelle Ave")
    create_claim(lease: create_lease(property: property))
    create_claim(lease: create_lease(property: property))

    import([["Row 3", "Inspection at 10205 Maydelle", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.first.claim_id
  end

  # -- approval amount linking -------------------------------------------------------

  test "links a thread citing a unique cents-bearing approval amount" do
    claim = create_claim(approved_benefit_amount: 1234.56)
    create_claim(approved_benefit_amount: 2000) # whole dollars — never used

    import([["Row 4", "This one was approved for $1,234.56 last week", "j", "06/15/25 02:30 PM"]])

    activity = ClaimActivity.sole
    assert_equal claim.id, activity.claim_id
    assert_equal "approval_amount", activity.link_method
  end

  test "does not link whole-dollar approval amounts" do
    create_claim(approved_benefit_amount: 2000)

    import([["Row 4", "approved at $2,000.00", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.sole.claim_id
  end

  test "does not link amounts shared by two claims" do
    create_claim(approved_benefit_amount: 1234.56)
    create_claim(approved_benefit_amount: 1234.56)

    import([["Row 4", "approved for $1,234.56", "j", "06/15/25 02:30 PM"]])

    assert_nil ClaimActivity.sole.claim_id
  end

  # -- tenant name linking ------------------------------------------------------------

  test "links a thread naming a tenant found in exactly one docs folder" do
    claim = create_claim(tracking_number: "812")
    docs_dir = Dir.mktmpdir("docs")
    FileUtils.mkdir_p(File.join(docs_dir, "812"))
    File.write(File.join(docs_dir, "812", "0904 Zorblatt Ledger.pdf"), "x")

    path = write_claims_xlsx([], comments: [
      ["Row 7", "spoke with tenant, Zorblatt agreed to a payment plan", "j", "06/15/25 02:30 PM"]
    ])
    CommentsImport.new(path, docs_dir: docs_dir).call

    activity = ClaimActivity.sole
    assert_equal claim.id, activity.claim_id
    assert_equal "tenant_name", activity.link_method
  end

  test "ignores dictionary words and document stopwords in filenames" do
    create_claim(tracking_number: "812")
    docs_dir = Dir.mktmpdir("docs")
    FileUtils.mkdir_p(File.join(docs_dir, "812"))
    File.write(File.join(docs_dir, "812", "Final Signed Lease.pdf"), "x")

    path = write_claims_xlsx([], comments: [
      ["Row 7", "the tenant, Signed the papers", "j", "06/15/25 02:30 PM"]
    ])
    CommentsImport.new(path, docs_dir: docs_dir).call

    assert_nil ClaimActivity.sole.claim_id
  end

  # -- conflicts and thread grouping ------------------------------------------------------

  test "conflicting methods leave the thread unlinked and count it" do
    cited = create_claim(tracking_number: "546")
    property = create_property(street_address: "10205 Maydelle Ave")
    create_claim(lease: create_lease(property: property))

    result = import([["Row 8", "claim #546 inspection at 10205 Maydelle", "j", "06/15/25 02:30 PM"]])

    assert_equal 1, result.conflicts
    assert_nil ClaimActivity.sole.claim_id
    refute_equal cited.id, ClaimActivity.sole.claim_id
  end

  test "all comments in a thread share the resolved link" do
    claim = create_claim(tracking_number: "546")

    result = import([
      ["Row 9", "initial note", "j", "06/15/25 02:30 PM"],
      ["Row 9", "follow-up: this is claim #546", "j", "06/16/25 09:00 AM"]
    ])

    assert_equal 2, result.imported
    assert_equal 1, result.linked_threads
    assert_equal [claim.id], ClaimActivity.pluck(:claim_id).uniq
  end

  test "higher-precedence methods win without conflict when they agree" do
    property = create_property(street_address: "10205 Maydelle Ave")
    claim = create_claim(tracking_number: "546", lease: create_lease(property: property))

    result = import([["Row 8", "claim #546 at 10205 Maydelle", "j", "06/15/25 02:30 PM"]])

    assert_equal 0, result.conflicts
    activity = ClaimActivity.sole
    assert_equal claim.id, activity.claim_id
    assert_equal "explicit_ref", activity.link_method
  end
end
