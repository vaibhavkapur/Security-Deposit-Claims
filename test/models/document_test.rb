require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    @claim = create_claim
  end

  test "requires name, path, byte size, storage key and content hash" do
    document = Document.new(claim: @claim)
    refute document.valid?
    %i[original_name relative_path byte_size storage_key content_hash].each do |attr|
      assert_includes document.errors[attr], "can't be blank", attr.to_s
    end
  end

  test "content hash must be unique" do
    existing = create_document(claim: @claim)
    copy = Document.new(claim: @claim, original_name: "x", relative_path: "x",
                        byte_size: 1, storage_key: "x",
                        content_hash: existing.content_hash)
    refute copy.valid?
    assert_includes copy.errors[:content_hash], "has already been taken"
  end

  test "storage_path joins the storage root and key" do
    document = create_document(claim: @claim, storage_key: "ab/cdef.pdf")
    assert_equal Document::STORAGE_ROOT.join("ab/cdef.pdf"), document.storage_path
  end

  test "extractable? follows the extraction doc type list" do
    DocumentExtraction::EXTRACTABLE_DOC_TYPES.each do |doc_type|
      assert create_document(claim: @claim, doc_type: doc_type).extractable?, doc_type
    end
    refute create_document(claim: @claim, doc_type: "photo").extractable?
    refute create_document(claim: @claim, doc_type: nil).extractable?
  end

  test "extraction_status reflects type and extraction state" do
    pending = create_document(claim: @claim, doc_type: "ledger")
    assert_equal "pending", pending.extraction_status

    extracted = create_document(claim: @claim, doc_type: "ledger",
                                extracted_json: { "line_items" => [] })
    assert_equal "extracted", extracted.extraction_status
    assert extracted.extracted?

    photo = create_document(claim: @claim, doc_type: "photo")
    assert_equal "not_extractable", photo.extraction_status
  end

  test "pending_extraction scope returns unextracted extractable documents" do
    pending = create_document(claim: @claim, doc_type: "ledger")
    create_document(claim: @claim, doc_type: "photo")
    create_document(claim: @claim, doc_type: "invoice",
                    extracted_json: { "line_items" => [] })

    assert_equal [pending], Document.pending_extraction.to_a
  end
end
