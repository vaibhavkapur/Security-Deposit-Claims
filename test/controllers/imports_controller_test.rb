require "test_helper"
require "zip"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  test "the import page renders with an empty database" do
    get root_path
    assert_response :success
  end

  test "the import page shows imported data and links analytics once decisions exist" do
    claim = create_claim
    get root_path
    assert_response :success
    refute_includes response.body, analytics_path

    create_decision(claim: claim)
    get root_path
    assert_includes response.body, analytics_path
  end

  # -- create (spreadsheet upload) --------------------------------------------

  test "create without a file redirects with an alert" do
    post import_path, params: {}
    assert_redirected_to new_import_path
    assert_match(/Choose an .xlsx file/, flash[:alert])
  end

  test "create imports the uploaded spreadsheet and its comments" do
    path = write_claims_xlsx(
      [claim_row("Tracking Number" => "101")],
      comments: [["Row 1", "note about claim #101", "j", "06/15/25 02:30 PM"]]
    )

    post import_path, params: { file: fixture_upload(path) }

    assert_redirected_to root_path
    assert Claim.exists?(tracking_number: "101")
    assert_equal 1, ClaimActivity.count
  end

  # -- create_documents (zip upload) ----------------------------------------------

  test "create_documents without a file redirects with an alert" do
    create_claim
    post import_documents_path, params: {}
    assert_redirected_to new_import_path
    assert_match(/Choose a .zip file/, flash[:alert])
  end

  test "create_documents requires claims to exist first" do
    file = Rack::Test::UploadedFile.new(write_empty_zip, "application/zip")
    post import_documents_path, params: { file: file }
    assert_redirected_to new_import_path
    assert_match(/Import the spreadsheet first/, flash[:alert])
  end

  # -- adjudicate lookup -------------------------------------------------------------

  test "adjudicate with no tracking numbers redirects with an alert" do
    post adjudicate_path, params: { tracking_numbers: "  " }
    assert_redirected_to root_path
    assert_match(/at least one tracking number/, flash[:alert])
  end

  test "adjudicate shows the stored decision for known claims" do
    claim = create_claim(tracking_number: "550")
    create_decision(claim: claim, outcome: "approve", amount: 123, reason: "test decision")

    post adjudicate_path, params: { tracking_numbers: "550, 999" }

    assert_response :success
    assert_includes response.body, "test decision"
  end

  # -- extract ----------------------------------------------------------------------------

  test "extract without an API key redirects with an alert" do
    with_env("ANTHROPIC_API_KEY", nil) do
      post extract_path
    end
    assert_redirected_to root_path
    assert_match(/ANTHROPIC_API_KEY is not set/, flash[:alert])
  end

  test "extract with no pending documents redirects with an alert" do
    with_env("ANTHROPIC_API_KEY", "test-key") do
      post extract_path
    end
    assert_redirected_to root_path
    assert_match(/No pending extractable documents/, flash[:alert])
  end

  # -- destroy -----------------------------------------------------------------------------

  test "destroy clears the database and redirects" do
    cleared = false
    DatabaseOverview.stub(:clear!, -> { cleared = true }) do
      delete import_path
    end
    assert_redirected_to root_path
    assert cleared, "expected DatabaseOverview.clear! to be called"
  end

  private

  def fixture_upload(path)
    Rack::Test::UploadedFile.new(
      path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end

  def write_empty_zip(path = File.join(Dir.mktmpdir("zip"), "docs.zip"))
    buffer = Zip::OutputStream.write_buffer do |zos|
      zos.put_next_entry("placeholder.txt")
      zos.write("x")
    end
    File.binwrite(path, buffer.string)
    path
  end

  def with_env(key, value)
    original = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end
end
