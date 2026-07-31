require "test_helper"
require "zip"

class DocumentsImportTest < ActiveSupport::TestCase
  setup do
    @created_storage_keys = []
  end

  teardown do
    # DocumentsImport writes into the shared storage/documents tree; remove
    # only the files this test created.
    @created_storage_keys.each do |key|
      FileUtils.rm_f(Document::STORAGE_ROOT.join(key))
    end
  end

  # entries: {"docs/670/ledger.pdf" => "file bytes"}
  def write_zip(entries)
    path = File.join(Dir.mktmpdir("zip"), "docs.zip")
    buffer = Zip::OutputStream.write_buffer do |zos|
      entries.each do |entry_path, content|
        zos.put_next_entry(entry_path)
        zos.write(content)
      end
    end
    File.binwrite(path, buffer.string)
    path
  end

  def import(entries)
    result = DocumentsImport.new(write_zip(entries)).call
    @created_storage_keys.concat(Document.pluck(:storage_key))
    result
  end

  test "imports files under a tracking-number folder onto that claim" do
    claim = create_claim(tracking_number: "670")

    result = import({ "docs/670/0904 Goldsby Ledger.pdf" => "pdf-bytes-#{SecureRandom.hex}" })

    assert_equal 1, result.created
    assert_empty result.skipped

    document = Document.sole
    assert_equal claim.id, document.claim_id
    assert_equal "0904 Goldsby Ledger.pdf", document.original_name
    assert_equal "ledger", document.doc_type
    assert_equal "filename", document.doc_type_source
    assert_equal "application/pdf", document.mime_type
    assert File.exist?(document.storage_path), "file should be written to storage"
  end

  test "finds the tracking folder anywhere in the path" do
    create_claim(tracking_number: "670")
    result = import({ "670/ledger.pdf" => "bytes-#{SecureRandom.hex}" })
    assert_equal 1, result.created
  end

  test "skips files whose folder matches no imported claim" do
    result = import({ "docs/999/ledger.pdf" => "bytes-#{SecureRandom.hex}" })

    assert_equal 0, result.created
    assert_equal "no claim #999", result.skipped.first[:reason]
  end

  test "skips files with no numeric folder in the path" do
    result = import({ "docs/misc/ledger.pdf" => "bytes-#{SecureRandom.hex}" })

    assert_equal 0, result.created
    assert_equal "no tracking folder", result.skipped.first[:reason]
  end

  test "skips duplicate content by hash" do
    create_claim(tracking_number: "670")
    create_claim(tracking_number: "671")
    same_bytes = "identical-#{SecureRandom.hex}"

    result = import({
      "docs/670/ledger.pdf" => same_bytes,
      "docs/671/Ledger copy.pdf" => same_bytes
    })

    assert_equal 1, result.created
    assert_equal 1, result.skipped.size
    assert_equal "duplicate content", result.skipped.first[:reason]
  end

  test "ignores macOS metadata and dotfiles" do
    create_claim(tracking_number: "670")

    result = import({
      "__MACOSX/docs/670/._ledger.pdf" => "junk",
      "docs/670/.DS_Store" => "junk",
      "docs/670/.hidden" => "junk",
      "docs/670/ledger.pdf" => "bytes-#{SecureRandom.hex}"
    })

    assert_equal 1, result.created
    assert_empty result.skipped
  end

  test "stores content hash and byte size" do
    create_claim(tracking_number: "670")
    bytes = "sized-content-#{SecureRandom.hex}"

    import({ "docs/670/ledger.pdf" => bytes })

    document = Document.sole
    assert_equal Digest::SHA256.hexdigest(bytes), document.content_hash
    assert_equal bytes.bytesize, document.byte_size
    assert document.storage_key.end_with?(".pdf")
  end

  # -- filename classification -----------------------------------------------

  test "classifies filenames by rule order" do
    classifier = DocumentsImport.new("unused")
    {
      "0904 Goldsby Ledger.pdf" => "ledger",
      "SDI Claim Form.pdf" => "sdi_form",
      "Move Out Statement.pdf" => "move_out_statement",
      "moveout statement.pdf" => "move_out_statement",
      "Itemization of charges.pdf" => "itemization",
      "Deposit Disposition.pdf" => "deposit_disposition",
      "Paint Invoice.pdf" => "invoice",
      "Receipt 123.pdf" => "invoice",
      "Signed Lease.pdf" => "lease",
      "Renewal Addendum.pdf" => "lease",
      "30 Day Notice.pdf" => "notice",
      "Closeout Summary.pdf" => "closeout_summary",
      "Move-Out Inspection.pdf" => "move_out_doc",
      "kitchen.jpg" => "photo",
      "kitchen.HEIC" => "photo",
      "random.txt" => "other"
    }.each do |filename, expected|
      assert_equal expected, classifier.send(:classify, filename), filename
    end
  end

  test "ledger rule wins over move-out in combined names" do
    classifier = DocumentsImport.new("unused")
    assert_equal "ledger", classifier.send(:classify, "Move Out Ledger.pdf")
  end

  test "doc_type_source is nil for unclassified files" do
    create_claim(tracking_number: "670")
    import({ "docs/670/mystery.txt" => "bytes-#{SecureRandom.hex}" })

    document = Document.sole
    assert_equal "other", document.doc_type
    assert_nil document.doc_type_source
  end
end
