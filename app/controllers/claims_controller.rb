class ClaimsController < ApplicationController
  def index
    @claims = Claim.includes(lease: :property)
                   .order(Arel.sql("NULLIF(regexp_replace(tracking_number, '\\D', '', 'g'), '')::bigint NULLS LAST"))
    @status_counts = Claim.group(:status).order(count_all: :desc).count
  end

  def show
    @claim = Claim.includes(:policy, :collection_record,
                            lease: [:property, :tenants, { property_manager: :pm_company }])
                  .find(params[:id])
    @activities = @claim.claim_activities.chronological
    @documents = @claim.documents.order(:doc_type, :original_name)
    @line_items = @claim.claim_line_items.includes(:document).order(:txn_date, :id)
    @decision = @claim.adjudication_decision
  end
end
