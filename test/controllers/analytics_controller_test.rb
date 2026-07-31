require "test_helper"

class AnalyticsControllerTest < ActionDispatch::IntegrationTest
  test "renders with no decisions at all" do
    get analytics_path
    assert_response :success
  end

  test "renders the comparison and simulation once decisions exist" do
    claim = create_claim(status: "Approved", approved_benefit_amount: 2000, claim_amount: 2000)
    create_decision(claim: claim, outcome: "approve", amount: 2000,
                    reason: "claim amount 2000.0 within policy max benefit 3000.0")
    declined = create_claim(status: "Declined", policy: nil)
    create_decision(claim: declined, outcome: "decline", amount: nil, reason: "no policy on file")

    get analytics_path

    assert_response :success
    assert_includes response.body, "Current rules"
  end

  test "renders decisions for claims the sheet left open" do
    claim = create_claim(status: "HOLD")
    create_decision(claim: claim, outcome: "approve", amount: 100, reason: "r")

    get analytics_path
    assert_response :success
  end
end
