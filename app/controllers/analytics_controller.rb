class AnalyticsController < ApplicationController
  def index
    @comparison = AdjudicationComparison.new.call
    @simulation = AdjudicationSimulation.new.call if @comparison.rows.any?
  end
end
