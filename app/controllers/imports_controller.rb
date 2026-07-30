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

    flash[:show_tables] = true
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

    flash[:show_tables] = true
    redirect_to root_path
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
  def adjudicate_one(tracking_number)
    claim = Claim.includes(:policy, :lease, :claim_line_items).find_by(tracking_number: tracking_number)
    return { tracking_number: tracking_number, claim: nil, decisions: [], ran_engine: false } if claim.nil?

    ran_engine = claim.adjudication_decisions.none?
    if ran_engine
      EligibilityEngine.new(claim).call
      LineItemReview.new(claim).call if claim.claim_line_items.any?
    end

    { tracking_number: tracking_number, claim: claim,
      decisions: claim.adjudication_decisions.order(:id).to_a, ran_engine: ran_engine }
  end
end
