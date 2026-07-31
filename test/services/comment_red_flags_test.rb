require "test_helper"

class CommentRedFlagsTest < ActiveSupport::TestCase
  setup do
    @claim = create_claim
  end

  test "returns empty array when there are no activities" do
    assert_equal [], CommentRedFlags.for(@claim)
  end

  test "returns empty array when comments are benign" do
    create_activity(claim: @claim, body: "Sent the PM a reminder about the ledger.")
    assert_equal [], CommentRedFlags.for(@claim)
  end

  test "flags explicit do-not-pay instructions" do
    create_activity(claim: @claim, body: "Per manager: DO NOT PAY this claim until docs arrive")
    flags = CommentRedFlags.for(@claim)
    assert_equal 1, flags.size
    assert_match(/do-not-pay instruction/, flags.first)
  end

  test "flags don't pay phrasing with apostrophe" do
    create_activity(claim: @claim, body: "don't pay yet, waiting on ledger")
    assert_match(/do-not-pay instruction/, CommentRedFlags.for(@claim).first)
  end

  test "flags tenant disputes" do
    create_activity(claim: @claim, body: "Tenant is disputing the charges")
    flags = CommentRedFlags.for(@claim)
    assert_equal 1, flags.size
    assert_match(/tenant dispute/, flags.first)
  end

  test "flags attorney or legal action" do
    create_activity(claim: @claim, body: "Tenant hired an attorney over the deposit")
    assert_match(/attorney or legal action/, CommentRedFlags.for(@claim).first)
  end

  test "flags lawsuit and litigation language" do
    create_activity(claim: @claim, body: "They threatened a lawsuit")
    assert_match(/attorney or legal action/, CommentRedFlags.for(@claim).first)
  end

  test "flags possible fraud or forgery" do
    create_activity(claim: @claim, body: "Signature appears forged on the lease")
    assert_match(/possible fraud or forgery/, CommentRedFlags.for(@claim).first)
  end

  test "returns one flag per pattern even with multiple matching comments" do
    create_activity(claim: @claim, body: "tenant dispute opened")
    create_activity(claim: @claim, body: "still disputing")
    flags = CommentRedFlags.for(@claim)
    assert_equal 1, flags.size
  end

  test "returns multiple flags when different patterns match" do
    create_activity(claim: @claim, body: "do not pay — tenant filed a lawsuit")
    flags = CommentRedFlags.for(@claim)
    assert_equal 2, flags.size
  end

  test "includes a truncated quote of the matching comment" do
    body = "Tenant dispute: " + "x" * 200
    create_activity(claim: @claim, body: body)
    flag = CommentRedFlags.for(@claim).first
    assert_match(/comments flag — tenant dispute: "/, flag)
    assert_operator flag.length, :<, body.length
  end

  test "matching is case-insensitive" do
    create_activity(claim: @claim, body: "POSSIBLE FRAUD reported")
    assert_match(/possible fraud or forgery/, CommentRedFlags.for(@claim).first)
  end
end
