require "axlsx"
require "tmpdir"

# Builds Claims.xlsx-shaped workbooks for import tests. The claims sheet is
# sheet 0 (what ClaimsImport reads); an optional "Comments" sheet matches the
# tab CommentsImport looks for.
module XlsxBuilder
  # Column order mirrors the real export closely enough for the importer,
  # which looks columns up by header name. :exception_flag stands in for the
  # real file's blank header cell (column AF).
  CLAIM_HEADERS = [
    "Tracking Number", "Status", "Claim Date", "Amount of Claim",
    "Termination Type", "Policy", "Group #", "Treaty #", "Max Benefit",
    "Lease Street Address", "Lease City", "Lease State", "Lease Zip",
    "Property Management Company", "Property Manager Name",
    "Lease Start Date", "Lease End Date", "Move-Out Date", "Monthly Rent",
    "Primary Tenant Employer Name", "Is there a 2nd Tenant?",
    "#2 Relationship", "#2 Tenant Employer Name", "#2 Tenant Employer Phone #",
    "Is there a 3rd Tenant?", "Pending Docs from PM", "Approval Date",
    "Approved Benefit Amount", "PM Explanation", "Hold Reason", "Posted Date",
    "PM Notification of Claim Received", "Audit Selection", :exception_flag,
    "Review Claim Adjudication", "Review Tenant Information",
    "Update YRIG Policy Info", "View PM Information", "Open Collections",
    "Send to Collections", "Collection Status", "Tenant Contacted",
    "Tenant Collection Status", "Agreed Tenant Settlement",
    "Agreed Tenant Settlement Date", "Collected Date", "Collected Amount",
    "Collection Processed Date"
  ].freeze

  # rows: array of hashes keyed by CLAIM_HEADERS entries.
  # comments: optional array of [row_ref, body, author, timestamp] arrays.
  def write_claims_xlsx(rows, comments: nil)
    path = File.join(Dir.mktmpdir("xlsx"), "claims.xlsx")
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Claims") do |sheet|
      sheet.add_row(CLAIM_HEADERS.map { |h| h == :exception_flag ? nil : h })
      rows.each do |row|
        unknown = row.keys - CLAIM_HEADERS
        raise ArgumentError, "unknown claim columns: #{unknown.inspect}" if unknown.any?

        sheet.add_row(CLAIM_HEADERS.map { |h| row[h] })
      end
    end
    if comments
      package.workbook.add_worksheet(name: "Comments") do |sheet|
        comments.each { |comment| sheet.add_row(comment) }
      end
    end
    package.serialize(path)
    path
  end

  def claim_row(overrides = {})
    {
      "Tracking Number" => "101",
      "Status" => "New",
      "Claim Date" => Date.new(2025, 6, 1),
      "Amount of Claim" => 2000,
      "Lease Street Address" => "500 Main St",
      "Lease City" => "Austin",
      "Lease State" => "TX",
      "Lease Zip" => "78701",
      "Policy" => "POL-1",
      "Max Benefit" => 3000,
      "Lease Start Date" => Date.new(2025, 1, 1),
      "Monthly Rent" => 1500
    }.merge(overrides)
  end
end

ActiveSupport::TestCase.include XlsxBuilder
