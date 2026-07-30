require "roo"

# Parses a Claims.xlsx upload and populates the database.
# Each spreadsheet row runs in its own transaction, so one bad row
# never aborts the rest of the import.
class ClaimsImport
  Result = Struct.new(:created, :skipped, :errors, keyword_init: true) do
    def total_processed = created + skipped.size + errors.size
  end

  EXCEPTION_FLAG_KEY = "__exception_flag__" # header cell for column AF is blank

  STATE_CODES = {
    "alabama" => "AL", "alaska" => "AK", "arizona" => "AZ", "arkansas" => "AR",
    "california" => "CA", "colorado" => "CO", "connecticut" => "CT", "delaware" => "DE",
    "florida" => "FL", "georgia" => "GA", "hawaii" => "HI", "idaho" => "ID",
    "illinois" => "IL", "indiana" => "IN", "iowa" => "IA", "kansas" => "KS",
    "kentucky" => "KY", "louisiana" => "LA", "maine" => "ME", "maryland" => "MD",
    "massachusetts" => "MA", "michigan" => "MI", "minnesota" => "MN", "mississippi" => "MS",
    "missouri" => "MO", "montana" => "MT", "nebraska" => "NE", "nevada" => "NV",
    "new hampshire" => "NH", "new jersey" => "NJ", "new mexico" => "NM", "new york" => "NY",
    "north carolina" => "NC", "north dakota" => "ND", "ohio" => "OH", "oklahoma" => "OK",
    "oregon" => "OR", "pennsylvania" => "PA", "rhode island" => "RI", "south carolina" => "SC",
    "south dakota" => "SD", "tennessee" => "TN", "texas" => "TX", "utah" => "UT",
    "vermont" => "VT", "virginia" => "VA", "washington" => "WA", "west virginia" => "WV",
    "wisconsin" => "WI", "wyoming" => "WY", "district of columbia" => "DC"
  }.freeze

  def initialize(file_path)
    @file_path = file_path.to_s
  end

  def call
    sheet = Roo::Spreadsheet.open(@file_path, extension: :xlsx).sheet(0)
    headers = sheet.row(1).map { |h| h.nil? ? EXCEPTION_FLAG_KEY : h.to_s.strip }
    result = Result.new(created: 0, skipped: [], errors: [])

    (2..sheet.last_row).each do |row_number|
      row = headers.zip(sheet.row(row_number)).to_h
      import_row(row, row_number, result)
    end

    result
  end

  private

  def import_row(row, row_number, result)
    tracking = text(row["Tracking Number"])
    status = text(row["Status"])

    if tracking.blank?
      result.skipped << { row: row_number, reason: "no tracking number" }
      return
    end
    if status&.casecmp?("Test Claim")
      result.skipped << { row: row_number, reason: "test claim" }
      return
    end
    if Claim.exists?(tracking_number: tracking)
      result.skipped << { row: row_number, reason: "tracking ##{tracking} already imported" }
      return
    end

    ActiveRecord::Base.transaction do
      lease = build_lease(row)
      build_tenants(row, lease)
      claim = build_claim(row, lease, tracking)
      build_collection(row, claim)
      result.created += 1
    end
  rescue StandardError => e
    result.errors << { row: row_number, error: e.message.truncate(200) }
  end

  def build_lease(row)
    property = Property.find_or_create_by!(
      street_address: text(row["Lease Street Address"]) || "(unknown)",
      city: text(row["Lease City"]),
      state: state_code(row["Lease State"]),
      zip: text(row["Lease Zip"])&.first(10)
    )

    manager = nil
    if (pm_name = text(row["Property Manager Name"]))
      company = PmCompany.find_or_create_by!(
        name: text(row["Property Management Company"]) || "(unknown)"
      )
      manager = company.property_managers.find_or_create_by!(name: pm_name)
    end

    Lease.find_or_create_by!(
      property: property,
      property_manager: manager,
      start_date: date(row["Lease Start Date"]),
      end_date: date(row["Lease End Date"]),
      move_out_date: date(row["Move-Out Date"]),
      monthly_rent: money(row["Monthly Rent"])
    )
  end

  def build_tenants(row, lease)
    lease.tenants.find_or_create_by!(tenant_number: 1) do |t|
      t.employer_name = text(row["Primary Tenant Employer Name"])
    end

    if yes?(row["Is there a 2nd Tenant?"])
      lease.tenants.find_or_create_by!(tenant_number: 2) do |t|
        t.relationship = text(row["#2 Relationship"])
        t.employer_name = text(row["#2 Tenant Employer Name"])
        t.employer_phone = text(row["#2 Tenant Employer Phone #"])&.first(20)
      end
    end

    if yes?(row["Is there a 3rd Tenant?"])
      lease.tenants.find_or_create_by!(tenant_number: 3)
    end
  end

  def build_claim(row, lease, tracking)
    policy = nil
    if (policy_number = text(row["Policy"]))
      policy = Policy.find_or_create_by!(policy_number: policy_number) do |p|
        p.group_number = text(row["Group #"])
        p.treaty_number = text(row["Treaty #"])
        p.max_benefit = money(row["Max Benefit"])
      end
    end

    approved = row["Approved Benefit Amount"]

    Claim.create!(
      lease: lease,
      policy: policy,
      tracking_number: tracking,
      claim_date: date(row["Claim Date"]),
      claim_amount: money(row["Amount of Claim"]),
      termination_type: text(row["Termination Type"]),
      status: text(row["Status"]),
      pending_docs_from_pm: text(row["Pending Docs from PM"]),
      approval_date: date(row["Approval Date"]),
      approved_benefit_amount: money(approved),
      approved_benefit_note: approved.is_a?(Numeric) ? nil : text(approved),
      pm_explanation: text(row["PM Explanation"]),
      hold_reason: text(row["Hold Reason"]),
      posted_date: date(row["Posted Date"]),
      pm_notified_at: date(row["PM Notification of Claim Received"]),
      audit_selected: row["Audit Selection"].present?,
      exception_flag: yes?(row[EXCEPTION_FLAG_KEY]),
      needs_adjudication_review: boolean(row["Review Claim Adjudication"]),
      tenant_info_reviewed: boolean(row["Review Tenant Information"]),
      policy_info_updated: boolean(row["Update YRIG Policy Info"]),
      pm_info_viewed: boolean(row["View PM Information"]),
      collections_opened: boolean(row["Open Collections"])
    )
  end

  COLLECTION_COLUMNS = [
    "Send to Collections", "Collection Status", "Tenant Contacted",
    "Tenant Collection Status", "Agreed Tenant Settlement",
    "Agreed Tenant Settlement Date", "Collected Date", "Collected Amount",
    "Collection Processed Date"
  ].freeze

  def build_collection(row, claim)
    return if COLLECTION_COLUMNS.none? { |col| row[col].present? }

    CollectionRecord.create!(
      claim: claim,
      referred_at: row["Send to Collections"].presence,
      collection_status: text(row["Collection Status"]),
      tenant_contacted_methods: text(row["Tenant Contacted"]),
      tenant_collection_status: text(row["Tenant Collection Status"]),
      settlement_amount: money(row["Agreed Tenant Settlement"]),
      settlement_date: date(row["Agreed Tenant Settlement Date"]),
      collected_date: date(row["Collected Date"]),
      collected_amount: money(row["Collected Amount"]),
      collection_processed_date: date(row["Collection Processed Date"])
    )
  end

  # -- cell coercion helpers ------------------------------------------------

  # Excel hands numeric-looking cells over as Floats (1.0, 29461.0);
  # render whole floats without the trailing ".0".
  def text(value)
    return nil if value.nil?

    str =
      if value.is_a?(Float) && value == value.to_i
        value.to_i.to_s
      else
        value.to_s
      end
    str = str.strip
    str.presence
  end

  def money(value)
    case value
    when Numeric then value.to_d.round(2)
    when String
      cleaned = value.gsub(/[$,\s]/, "")
      cleaned.match?(/\A-?\d+(\.\d+)?\z/) ? cleaned.to_d.round(2) : nil
    end
  end

  def date(value)
    case value
    when Date, DateTime then value.to_date
    when String then Date.parse(value) rescue nil
    end
  end

  def yes?(value)
    value.to_s.strip.downcase.in?(%w[yes true y])
  end

  # Tri-state: "Yes" => true, "No" => false, blank => nil
  def boolean(value)
    str = value.to_s.strip.downcase
    return true if str.in?(%w[yes true y])
    return false if str.in?(%w[no false n])

    nil
  end

  def state_code(value)
    str = text(value)
    return nil if str.nil?
    return str.upcase if str.length == 2

    STATE_CODES[str.downcase] || str.first(2).upcase
  end
end
