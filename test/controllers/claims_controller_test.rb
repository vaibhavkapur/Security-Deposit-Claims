require "test_helper"

class ClaimsControllerTest < ActionDispatch::IntegrationTest
  test "index lists claims ordered by numeric tracking number" do
    thirty = create_claim(tracking_number: "30", status: "Approved")
    four = create_claim(tracking_number: "4", status: "Approved")

    get claims_path

    assert_response :success
    assert_operator response.body.index(claim_path(four)), :<,
                    response.body.index(claim_path(thirty)),
                    "claim 4 should be listed before claim 30"
  end

  test "show renders the claim with its decision, activities and line items" do
    claim = create_claim(tracking_number: "777")
    create_activity(claim: claim, body: "called the PM about docs")
    item = create_line_item(claim: claim, description: "wall repair", amount: 120)
    item.document.update!(extracted_json: { "line_items" => [] })
    create_decision(claim: claim, outcome: "approve", amount: 120, reason: "test decision")

    get claim_path(claim)

    assert_response :success
    assert_includes response.body, "777"
    assert_includes response.body, "called the PM about docs"
    assert_includes response.body, "wall repair"
  end

  test "show 404s for unknown claims" do
    get claim_path(id: 999_999)
    assert_response :not_found
  end
end
