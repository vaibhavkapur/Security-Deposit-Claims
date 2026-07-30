class ActivitiesController < ApplicationController
  PER_PAGE = 25

  def unlinked
    @page = [params[:page].to_i, 1].max
    thread_refs = ClaimActivity.unlinked.where.not(source_row_ref: nil)
                               .group(:source_row_ref)
                               .order(Arel.sql("max(occurred_at) DESC"))
                               .limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
                               .pluck(:source_row_ref)
    @threads = ClaimActivity.where(source_row_ref: thread_refs)
                            .chronological
                            .group_by(&:source_row_ref)
                            .sort_by { |_ref, list| -list.map(&:occurred_at).max.to_i }
    @total_threads = ClaimActivity.unlinked.where.not(source_row_ref: nil)
                                  .distinct.count(:source_row_ref)
    @pages = (@total_threads / PER_PAGE.to_f).ceil
  end
end
