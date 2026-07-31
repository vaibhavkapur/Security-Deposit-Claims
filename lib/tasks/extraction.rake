namespace :extraction do
  desc "Extract line items from pending documents. LIMIT=n bounds the batch (default 10, 'all' for everything)."
  task run: :environment do
    abort "ANTHROPIC_API_KEY is not set — export it before running extraction." if ENV["ANTHROPIC_API_KEY"].blank?

    limit = ENV.fetch("LIMIT", "10")
    scope = Document.pending_extraction.order(:id)
    scope = scope.limit(Integer(limit)) unless limit == "all"

    total = scope.count
    puts "Extracting #{total} documents (of #{Document.pending_extraction.count} pending extractable)..."

    scope.each_with_index do |document, i|
      DocumentExtraction.new(document).call
      document.reload
      items = ClaimLineItem.where(document_id: document.id).count
      puts format("[%d/%d] doc %d (%s, claim #%s): %s",
                  i + 1, total, document.id, document.doc_type,
                  document.claim.tracking_number,
                  document.extracted? ? "extracted — #{items} line items" : "not extracted (see log)")
    end

    puts "\nExtracted: #{Document.where.not(extracted_json: nil).count}, pending extractable: #{Document.pending_extraction.count}"
    puts "Line items total: #{ClaimLineItem.count}"
  end
end
