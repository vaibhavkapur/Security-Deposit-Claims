class ImportsController < ApplicationController
  def new
    load_tables
  end

  def adjudicate
    numbers = params[:tracking_numbers].to_s.split(/[\s,;]+/).reject(&:blank?).uniq
    if numbers.empty?
      redirect_to root_path, alert: "Enter at least one tracking number." and return
    end

    @tracking_numbers_input = params[:tracking_numbers]
    @adjudication_results = numbers.map { |tn| adjudicate_one(tn) }

    load_tables
    render :new
  end

  def create
    file = params[:file]
    if file.blank?
      redirect_to new_import_path, alert: "Choose an .xlsx file first." and return
    end

    ClaimsImport.new(file.tempfile.path).call
    CommentsImport.new(file.tempfile.path).call

    redirect_to root_path
  end

  def create_documents
    file = params[:file]
    if file.blank?
      redirect_to new_import_path, alert: "Choose a .zip file first." and return
    end
    if Claim.none?
      redirect_to new_import_path,
                  alert: "Import the spreadsheet first — documents link to claims by tracking number." and return
    end

    DocumentsImport.new(file.tempfile.path).call

    redirect_to root_path
  end

  # Runs Claude extraction (DocumentExtraction) over every pending extractable
  # document — one API call per document, ExtractionBatch::THREADS at a time —
  # then Stage 2 adjudication, so one click takes claims from PDFs to decisions.
  def extract
    if ENV["ANTHROPIC_API_KEY"].blank?
      redirect_to root_path, alert: "ANTHROPIC_API_KEY is not set — export it and restart the server." and return
    end

    scope = Document.pending_extraction.order(:id)
    if scope.none?
      redirect_to root_path, alert: "No pending extractable documents." and return
    end

    documents = ExtractionBatch.call(scope)
    summary = documents.map(&:extraction_status).tally
                       .map { |status, count| "#{count} #{status.humanize.downcase}" }.join(", ")

    decided = AdjudicationBatch.call
    # AdjudicationBatch skips already-decided claims, so re-review the ones
    # this batch added line items to — Stage 2's ledger ruling overrides
    # their now-stale Stage 1 decisions.
    Claim.where(id: documents.map(&:claim_id).uniq)
         .includes(:policy, :lease, :claim_line_items, :claim_activities)
         .each { |claim| LineItemReview.new(claim).call }

    redirect_to root_path,
                notice: "Extraction finished: #{summary}. #{ClaimLineItem.count} line items total. " \
                        "Stage 2: #{decided} newly adjudicated, #{AdjudicationDecision.count} decisions overall."
  end

  def destroy
    DatabaseOverview.clear!
    redirect_to root_path
  end

  private

  def load_tables
    @spreadsheet_tables = DatabaseOverview.spreadsheet_tables
    @pdf_tables = DatabaseOverview.pdf_tables
    @adjudication_tables = DatabaseOverview.adjudication_tables
  end

  # Looks up a claim by tracking number and returns its adjudication decisions,
  # running the rules engine first if the claim has never been adjudicated.
  # Read-only lookup: decisions are pre-computed for every claim (see
  # AdjudicationBatch), so the form only fetches what's already in the DB.
  def adjudicate_one(tracking_number)
    claim = Claim.find_by(tracking_number: tracking_number)
    { tracking_number: tracking_number, claim: claim,
      decision: claim&.adjudication_decision }
  end
end
