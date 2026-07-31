require "test_helper"

class DocumentExtractionTest < ActiveSupport::TestCase
  FakeBlock = Struct.new(:type, :input, keyword_init: true)
  FakeResponse = Struct.new(:stop_reason, :content, keyword_init: true)

  setup do
    @claim = create_claim
    @written_paths = []
  end

  teardown do
    @written_paths.each { |path| FileUtils.rm_f(path) }
  end

  # Creates a document whose storage file actually exists.
  def document_with_file(content: "pdf-#{SecureRandom.hex}", **attrs)
    document = create_document(claim: @claim, **attrs)
    path = document.storage_path
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, content)
    @written_paths << path
    document
  end

  def fake_client_returning(response)
    client = Object.new
    messages = Object.new
    messages.define_singleton_method(:create) { |**_kwargs| response }
    client.define_singleton_method(:messages) { messages }
    client
  end

  def extract(document, response)
    service = DocumentExtraction.new(document)
    service.stub(:client, fake_client_returning(response)) { service.call }
  end

  def tool_response(input)
    FakeResponse.new(stop_reason: :tool_use,
                     content: [FakeBlock.new(type: :tool_use, input: input)])
  end

  # -- guards, no API call needed -------------------------------------------

  test "skips documents whose type is not extractable" do
    document = create_document(claim: @claim, doc_type: "photo")

    assert_equal document, DocumentExtraction.new(document).call
    assert_nil document.reload.extracted_json
    assert_empty ClaimLineItem.all
  end

  test "skips when the file is missing from storage" do
    document = create_document(claim: @claim) # no file written

    assert_equal document, DocumentExtraction.new(document).call
    assert_nil document.reload.extracted_json
  end

  test "skips files over the size limit" do
    document = document_with_file
    File.stub(:size, DocumentExtraction::MAX_FILE_BYTES + 1) do
      assert_equal document, DocumentExtraction.new(document).call
    end
    assert_nil document.reload.extracted_json
  end

  test "skips unsupported mime types" do
    document = document_with_file(mime_type: "text/plain")

    assert_equal document, DocumentExtraction.new(document).call
    assert_nil document.reload.extracted_json
  end

  # -- model responses ---------------------------------------------------------

  test "promotes extracted line items into claim_line_items" do
    document = document_with_file
    response = tool_response({
      document_date: "2025-06-01",
      line_items: [
        { date: "2025-05-01", description: "May rent", category: "unpaid_rent", amount: 1500 },
        { date: nil, description: "Cleaning", category: "cleaning", amount: 250.5 },
        { date: "2025-05-02", description: "Payment", category: "payment", amount: -800 }
      ]
    })

    extract(document, response)

    items = ClaimLineItem.order(:id)
    assert_equal 3, items.size
    assert_equal ["May rent", "Cleaning", "Payment"], items.map(&:description)
    assert_equal [1500, 250.5, -800], items.map(&:amount)
    assert_equal Date.new(2025, 5, 1), items.first.txn_date
    assert_nil items.second.txn_date
    assert items.all? { |i| i.claim_id == @claim.id && i.document_id == document.id }
    # Column defaults apply until Stage 2 classifies them.
    assert items.all? { |i| i.disposition == "denied" }
    assert_equal "2025-06-01", document.reload.extracted_json["document_date"]
  end

  test "replaces previously extracted line items for the document" do
    document = document_with_file
    stale = create_line_item(claim: @claim, document: document, description: "stale")

    extract(document, tool_response({ line_items: [
      { description: "fresh", category: "damage", amount: 100 }
    ] }))

    refute ClaimLineItem.exists?(stale.id)
    assert_equal ["fresh"], ClaimLineItem.where(document_id: document.id).pluck(:description)
  end

  test "does not touch line items from other documents" do
    document = document_with_file
    other_doc = create_document(claim: @claim)
    other_item = create_line_item(claim: @claim, document: other_doc)

    extract(document, tool_response({ line_items: [] }))

    assert ClaimLineItem.exists?(other_item.id)
  end

  test "blank descriptions and categories get fallbacks" do
    document = document_with_file

    extract(document, tool_response({ line_items: [
      { description: "", category: "", amount: 10 }
    ] }))

    item = ClaimLineItem.sole
    assert_equal "(blank)", item.description
    assert_equal "other", item.category
  end

  test "unparseable transaction dates become nil" do
    document = document_with_file

    extract(document, tool_response({ line_items: [
      { date: "n/a", description: "x", category: "other", amount: 10 }
    ] }))

    assert_nil ClaimLineItem.sole.txn_date
  end

  test "an empty line_items array still records the extraction" do
    document = document_with_file

    extract(document, tool_response({ line_items: [], notes: "no charges listed" }))

    assert_empty ClaimLineItem.all
    assert document.reload.extracted?
    assert_equal "no charges listed", document.extracted_json["notes"]
  end

  test "a refusal leaves the document unextracted" do
    document = document_with_file
    response = FakeResponse.new(stop_reason: :refusal, content: [])

    assert_equal document, extract(document, response)
    assert_nil document.reload.extracted_json
  end

  test "a response without a tool_use block leaves the document unextracted" do
    document = document_with_file
    response = FakeResponse.new(stop_reason: :end_turn,
                                content: [FakeBlock.new(type: :text, input: nil)])

    assert_equal document, extract(document, response)
    assert_nil document.reload.extracted_json
  end

  test "invalid extracted data rolls back both line items and extracted_json" do
    document = document_with_file

    extract(document, tool_response({ line_items: [
      { description: "ok", category: "damage", amount: 100 },
      { description: "bad", category: "damage", amount: nil }
    ] }))

    assert_empty ClaimLineItem.all
    assert_nil document.reload.extracted_json
  end

  test "images are sent as image content blocks" do
    document = document_with_file(mime_type: "image/png",
                                  original_name: "ledger.png", doc_type: "ledger")

    extract(document, tool_response({ line_items: [
      { description: "from image", category: "damage", amount: 50 }
    ] }))

    assert_equal ["from image"], ClaimLineItem.pluck(:description)
  end
end
