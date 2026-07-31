require "test_helper"

class ActivitiesControllerTest < ActionDispatch::IntegrationTest
  def create_thread(row_ref, occurred_at: Time.zone.local(2025, 5, 1), comments: 1)
    comments.times do |i|
      create_activity(claim: nil, body: "note #{row_ref}-#{i}",
                      occurred_at: occurred_at + i.hours)
    end
    ClaimActivity.where("body LIKE ?", "note #{row_ref}-%").update_all(source_row_ref: row_ref)
  end

  test "renders unlinked threads grouped by row ref" do
    create_thread("Row 1", comments: 2)
    create_thread("Row 2")

    get unlinked_activities_path

    assert_response :success
    assert_includes response.body, "note Row 1-0"
    assert_includes response.body, "note Row 1-1"
    assert_includes response.body, "note Row 2-0"
  end

  test "excludes linked activities and unlinked ones without a row ref" do
    create_activity(claim: create_claim, body: "linked note")
    create_activity(claim: nil, body: "no ref note")

    get unlinked_activities_path

    assert_response :success
    refute_includes response.body, "linked note"
    refute_includes response.body, "no ref note"
  end

  test "paginates past 25 threads" do
    30.times { |i| create_thread("Row #{i}", occurred_at: Time.zone.local(2025, 1, 1) + i.days) }

    get unlinked_activities_path
    assert_response :success
    # newest threads first — Row 29 on page 1
    assert_includes response.body, "note Row 29-0"
    refute_includes response.body, "note Row 0-0"

    get unlinked_activities_path(page: 2)
    assert_response :success
    assert_includes response.body, "note Row 0-0"
  end

  test "clamps the page parameter to at least 1" do
    create_thread("Row 1")
    get unlinked_activities_path(page: -5)
    assert_response :success
    assert_includes response.body, "note Row 1-0"
  end
end
