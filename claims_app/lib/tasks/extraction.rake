namespace :extraction do
  desc "Extract line items from pending documents. LIMIT=n bounds the batch (default 10, 'all' for everything)."
  task run: :environment do
    abort "ANTHROPIC_API_KEY is not set — export it before running extraction." if ENV["ANTHROPIC_API_KEY"].blank?

    limit = ENV.fetch("LIMIT", "10")
    scope = Document.where(extraction_status: "pending",
                           doc_type: DocumentExtraction::EXTRACTABLE_DOC_TYPES)
                    .order(:id)
    scope = scope.limit(Integer(limit)) unless limit == "all"

    total = scope.count
    puts "Extracting #{total} documents (of #{Document.where(extraction_status: 'pending', doc_type: DocumentExtraction::EXTRACTABLE_DOC_TYPES).count} pending extractable)..."

    scope.each_with_index do |document, i|
      DocumentExtraction.new(document).call
      document.reload
      items = ClaimLineItem.where(document_id: document.id).count
      puts format("[%d/%d] doc %d (%s, claim #%s): %s%s",
                  i + 1, total, document.id, document.doc_type,
                  document.claim.tracking_number, document.extraction_status,
                  document.extraction_status == "extracted" ? " — #{items} line items" : " — #{document.extraction_error}")
    end

    puts "\nStatus summary: #{Document.group(:extraction_status).count}"
    puts "Line items total: #{ClaimLineItem.count}"
  end
end
