require "test_helper"

class DatabaseOverviewTest < ActiveSupport::TestCase
  test "tables reports name, counts, sample rows and columns without timestamps" do
    claim = create_claim

    table = DatabaseOverview.tables([Claim]).sole

    assert_equal "claims", table[:name]
    assert_equal 1, table[:count]
    assert_equal 1, table[:total]
    assert_includes table[:columns], "tracking_number"
    refute_includes table[:columns], "created_at"
    assert_equal [claim], table[:rows].to_a
  end

  test "model groups cover every imported model exactly once" do
    grouped = DatabaseOverview::SPREADSHEET_MODELS +
              DatabaseOverview::PDF_MODELS +
              DatabaseOverview::ADJUDICATION_MODELS
    assert_equal grouped, DatabaseOverview::MODELS
    assert_equal grouped.uniq, grouped
  end

  test "documents display all rows until any extraction exists, then only extracted" do
    claim = create_claim
    plain = create_document(claim: claim)

    assert_equal [plain], DatabaseOverview.display_scope(Document).to_a

    extracted = create_document(claim: claim, extracted_json: { "line_items" => [] })
    assert_equal [extracted], DatabaseOverview.display_scope(Document).to_a

    # count reflects the display scope; total reflects the whole table
    table = DatabaseOverview.pdf_tables.find { |t| t[:name] == "documents" }
    assert_equal 1, table[:count]
    assert_equal 2, table[:total]
  end

  test "adjudication decision samples alternate outcomes and dedupe reasons" do
    4.times do
      claim = create_claim
      create_decision(claim: claim, outcome: "decline", amount: nil, reason: "no policy on file")
    end
    approved = create_claim
    create_decision(claim: approved, outcome: "approve", amount: 10, reason: "looks fine")

    rows = DatabaseOverview.sample_rows(AdjudicationDecision, AdjudicationDecision.all)

    # Identical decline reasons collapse to one representative + the approval.
    assert_equal 2, rows.size
    assert_equal %w[approve decline], rows.map(&:outcome).sort
  end

  test "clear! truncates every imported table and removes document storage" do
    create_claim
    create_activity(claim: Claim.first)

    removed_paths = []
    FileUtils.stub(:rm_rf, ->(path) { removed_paths << path }) do
      DatabaseOverview.clear!
    end

    DatabaseOverview::MODELS.each do |model|
      assert_equal 0, model.count, "#{model.name} should be empty"
    end
    assert_equal [Document::STORAGE_ROOT], removed_paths
  end
end
