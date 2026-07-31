require "test_helper"

class ExtractionBatchTest < ActiveSupport::TestCase
  # Stub DocumentExtraction with a recorder: worker threads use their own DB
  # connections, which cannot see this test's uncommitted data.
  class Recorder
    def initialize(seen)
      @seen = seen
    end

    def call
      @seen << @document_id
    end

    def for(document)
      @document_id = document.id
      self
    end
  end

  test "runs an extraction for every document in the scope" do
    claim = create_claim
    documents = 3.times.map { create_document(claim: claim) }
    seen = Queue.new

    factory = ->(document) { Recorder.new(seen).for(document) }
    DocumentExtraction.stub(:new, factory) do
      ExtractionBatch.call(Document.where(id: documents.map(&:id)), threads: 2)
    end

    processed = 3.times.map { seen.pop(true) }
    assert_equal documents.map(&:id).sort, processed.sort
  end

  test "returns the documents reloaded" do
    claim = create_claim
    document = create_document(claim: claim)

    factory = ->(_doc) { Recorder.new(Queue.new).for(_doc) }
    returned = DocumentExtraction.stub(:new, factory) do
      ExtractionBatch.call(Document.where(id: document.id))
    end

    assert_equal [document.id], returned.map(&:id)
  end

  test "handles an empty scope without spawning workers" do
    assert_equal [], ExtractionBatch.call(Document.none)
  end
end
