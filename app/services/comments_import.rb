require "roo"

# Imports the "Comments" tab of a Claims.xlsx upload into claim_activities.
#
# The Comments tab references claims by sheet position ("Row 94"), but the
# claims tab was re-sorted after export, so positions are unreliable (verified:
# approval amounts stated in comments land on the wrong claims when mapped
# positionally). Each comment thread is therefore linked to a claim only when
# its content unambiguously matches, via one of four methods (in precedence
# order, all requiring a single-claim match):
#
#   explicit_ref    - "#546" / "tracking #212" references in the text
#   address         - a street address unique to one claim found in the text
#   approval_amount - "approv... $X" where X (with cents) matches exactly one
#                     claim's approved_benefit_amount
#   tenant_name     - a distinctive surname from the claim's docs folder
#                     (folder name = tracking number), capitalized in the
#                     comment and absent from the system dictionary
#
# Threads that no method links — or where methods disagree — stay unlinked
# (claim_id NULL) but keep their source_row_ref so the thread grouping
# survives for later (e.g. model-assisted) linking.
class CommentsImport
  Result = Struct.new(:imported, :linked_threads, :conflicts, keyword_init: true)

  COMMENTS_SHEET = "Comments".freeze
  TIMESTAMP_FORMAT = "%m/%d/%y %I:%M %p".freeze

  REF_CONTEXT_STOPWORDS = %w[unit apt apartment phone account acct check cheque invoice].freeze
  DOC_FILENAME_STOPWORDS = %w[
    lease ledger statement letter close closeout summary invoice notice deposit
    security claim addendum final signed docusign moveout makeready propertyware
    appfolio buildium
  ].freeze
  SYSTEM_DICTIONARY = "/usr/share/dict/words".freeze

  def initialize(file_path, docs_dir: Rails.root.join("..", "docs"))
    @file_path = file_path.to_s
    @docs_dir = docs_dir.to_s
  end

  def call
    workbook = Roo::Spreadsheet.open(@file_path, extension: :xlsx)
    return Result.new(imported: 0, linked_threads: 0, conflicts: 0) unless
      workbook.sheets.include?(COMMENTS_SHEET)

    sheet = workbook.sheet(COMMENTS_SHEET)
    comments = parse_comments(sheet)
    blobs = comments.group_by { |c| c[:row_ref] }
                    .transform_values { |list| list.map { |c| c[:body] }.join(" ") }

    links, conflicts = resolve_links(blobs)

    imported = 0
    ActiveRecord::Base.transaction do
      comments.each do |comment|
        claim_id, method = links[comment[:row_ref]]
        ClaimActivity.create!(
          claim_id: claim_id,
          author: comment[:author],
          body: comment[:body],
          occurred_at: comment[:occurred_at],
          source_row_ref: comment[:row_ref],
          link_method: method
        )
        imported += 1
      end
    end

    Result.new(imported: imported, linked_threads: links.size, conflicts: conflicts)
  end

  private

  def parse_comments(sheet)
    (1..sheet.last_row).filter_map do |i|
      row_ref, body, author, timestamp = sheet.row(i)
      occurred_at = parse_timestamp(timestamp)
      next if body.blank? || occurred_at.nil?

      {
        row_ref: row_ref.to_s.match?(/\ARow \d+\z/) ? row_ref.to_s : nil,
        body: body.to_s,
        author: author.presence&.to_s || "unknown",
        occurred_at: occurred_at
      }
    end
  end

  def parse_timestamp(value)
    case value
    when DateTime, Time then value
    when String then DateTime.strptime(value.strip, TIMESTAMP_FORMAT) rescue nil
    end
  end

  # -- linking --------------------------------------------------------------

  def resolve_links(blobs)
    methods = {
      "explicit_ref" => explicit_ref_links(blobs),
      "address" => address_links(blobs),
      "approval_amount" => approval_amount_links(blobs),
      "tenant_name" => tenant_name_links(blobs)
    }

    links = {}
    conflicted = Set.new
    methods.each do |method, found|
      found.each do |row_ref, claim_id|
        next if conflicted.include?(row_ref)

        if links.key?(row_ref) && links[row_ref].first != claim_id
          conflicted << row_ref
          links.delete(row_ref)
        elsif !links.key?(row_ref)
          links[row_ref] = [claim_id, method]
        end
      end
    end
    [links, conflicted.size]
  end

  def claim_ids_by_tracking
    @claim_ids_by_tracking ||= Claim.pluck(:tracking_number, :id).to_h
  end

  def explicit_ref_links(blobs)
    blobs.filter_map do |row_ref, blob|
      next if row_ref.nil?

      candidates = Set.new
      blob.scan(/(?<![\w])#\s?(\d{1,4})\b/) do |(number)|
        context = Regexp.last_match.pre_match.last(20).downcase
        next if REF_CONTEXT_STOPWORDS.any? { |w| context.include?(w) }
        next if number.to_i <= 3 # avoid "#2 tenant" style references

        candidates << number if claim_ids_by_tracking.key?(number)
      end
      [row_ref, claim_ids_by_tracking[candidates.first]] if candidates.size == 1
    end.to_h
  end

  def address_links(blobs)
    keys = {} # "10205 maydelle" => claim_id, nil when ambiguous
    Claim.joins(lease: :property).pluck("properties.street_address", :id).each do |address, claim_id|
      key = address.to_s[/\A\d+\s+\w{4,}/]&.downcase or next
      keys[key] = keys.key?(key) ? nil : claim_id
    end
    keys.compact!

    match_unique(blobs) do |blob|
      down = blob.downcase
      keys.filter_map { |key, claim_id| claim_id if down.include?(key) }
    end
  end

  def approval_amount_links(blobs)
    amounts = Claim.where.not(approved_benefit_amount: nil)
                   .where("approved_benefit_amount % 1 <> 0") # cents-bearing only
                   .group(:approved_benefit_amount)
                   .having("count(*) = 1")
                   .pluck(:approved_benefit_amount)
    ids = Claim.where(approved_benefit_amount: amounts)
               .pluck(:approved_benefit_amount, :id)
               .to_h { |amount, id| [amount.to_d, id] }

    match_unique(blobs) do |blob|
      blob.scan(/approv\w*[^.]{0,40}?\$?([\d,]+\.\d{2})/i).filter_map do |(raw)|
        ids[raw.delete(",").to_d]
      end
    end
  end

  def tenant_name_links(blobs)
    tokens = docs_filename_tokens
    return {} if tokens.empty?

    match_unique(blobs) do |blob|
      # proper-noun usage only: capitalized mid-sentence
      proper_nouns = blob.scan(/(?<=[a-z,;\s])([A-Z][a-z]{4,})/).flatten.map(&:downcase).uniq
      proper_nouns.filter_map { |word| tokens[word] }
    end
  end

  # Distinctive filename tokens appearing in exactly one docs folder,
  # mapped to that folder's claim. Folder name = tracking number.
  def docs_filename_tokens
    return {} unless File.directory?(@docs_dir)

    dictionary = File.readlines(SYSTEM_DICTIONARY, chomp: true).map(&:downcase).to_set
    token_folders = Hash.new { |h, k| h[k] = Set.new }
    Dir.children(@docs_dir).each do |folder|
      next unless folder.match?(/\A\d+\z/) && claim_ids_by_tracking.key?(folder)

      Dir.children(File.join(@docs_dir, folder)).each do |filename|
        filename.scan(/[A-Za-z]{5,}/).each do |token|
          token = token.downcase
          next if DOC_FILENAME_STOPWORDS.include?(token) || dictionary.include?(token)

          token_folders[token] << folder
        end
      end
    end
    token_folders.filter_map do |token, folders|
      [token, claim_ids_by_tracking[folders.first]] if folders.size == 1
    end.to_h
  rescue Errno::ENOENT
    {}
  end

  def match_unique(blobs)
    blobs.filter_map do |row_ref, blob|
      next if row_ref.nil?

      hits = yield(blob).uniq
      [row_ref, hits.first] if hits.size == 1
    end.to_h
  end
end
