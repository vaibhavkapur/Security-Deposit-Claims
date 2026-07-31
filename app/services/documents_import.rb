require "zip"
require "digest"

# Imports a zip of claim documents (e.g. docs.zip) into the documents table.
#
# The zip is expected to contain one folder per claim, named by tracking
# number ("docs/670/0904 Goldsby Ledger.pdf" or "670/..."), matching how the
# PM document folders are organized. Files are stored under
# storage/documents/ keyed by content hash (deduplicating re-uploads) and
# classified by filename; files whose folder matches no imported claim are
# skipped and reported.
class DocumentsImport
  Result = Struct.new(:created, :skipped, :errors, keyword_init: true)

  IGNORED_BASENAMES = [".DS_Store", "Thumbs.db"].freeze

  # Checked in order; first match wins.
  DOC_TYPE_RULES = [
    ["ledger", :ledger],
    ["sdi", :sdi_form],
    [/move.?out.{0,20}statement/, :move_out_statement],
    [/itemiz/, :itemization],
    ["disposition", :deposit_disposition],
    [/invoice|receipt|billable/, :invoice],
    [/lease|addendum|renewal|application/, :lease],
    ["notice", :notice],
    [/close.?out|closeout/, :closeout_summary],
    [/move.?out|inspection|evaluation/, :move_out_doc]
  ].freeze

  PHOTO_EXTENSIONS = %w[.jpg .jpeg .png .gif .heic].freeze

  def initialize(zip_path)
    @zip_path = zip_path.to_s
  end

  def call
    result = Result.new(created: 0, skipped: [], errors: [])
    claim_ids = Claim.pluck(:tracking_number, :id).to_h

    Zip::File.open(@zip_path) do |zip|
      zip.each do |entry|
        next unless entry.file?

        path = entry.name
        basename = File.basename(path)
        next if path.include?("__MACOSX") || basename.start_with?(".") ||
                IGNORED_BASENAMES.include?(basename)

        import_entry(entry, path, basename, claim_ids, result)
      end
    end

    result
  end

  private

  def import_entry(entry, path, basename, claim_ids, result)
    tracking = path.split("/").find { |segment| segment.match?(/\A\d+\z/) }
    claim_id = claim_ids[tracking]
    if claim_id.nil?
      result.skipped << { path: path, reason: tracking ? "no claim ##{tracking}" : "no tracking folder" }
      return
    end

    bytes = entry.get_input_stream.read
    hash = Digest::SHA256.hexdigest(bytes)
    if Document.exists?(content_hash: hash)
      result.skipped << { path: path, reason: "duplicate content" }
      return
    end

    storage_key = File.join(hash[0, 2], hash + File.extname(basename).downcase)
    full_path = Document::STORAGE_ROOT.join(storage_key)
    FileUtils.mkdir_p(full_path.dirname)
    File.binwrite(full_path, bytes)

    doc_type = classify(basename)
    extractable = DocumentExtraction::EXTRACTABLE_DOC_TYPES.include?(doc_type)
    Document.create!(
      claim_id: claim_id,
      original_name: basename,
      relative_path: path,
      content_hash: hash,
      mime_type: Marcel::MimeType.for(name: basename),
      byte_size: bytes.bytesize,
      doc_type: doc_type,
      doc_type_source: doc_type == "other" ? nil : "filename",
      storage_key: storage_key,
      extraction_status: extractable ? "pending" : "not_extractable"
    )
    result.created += 1
  rescue StandardError => e
    result.errors << { path: path, error: e.message.truncate(200) }
  end

  def classify(basename)
    name = basename.downcase
    DOC_TYPE_RULES.each do |pattern, type|
      matched = pattern.is_a?(Regexp) ? name.match?(pattern) : name.include?(pattern)
      return type.to_s if matched
    end
    return "photo" if PHOTO_EXTENSIONS.include?(File.extname(name))

    "other"
  end
end
