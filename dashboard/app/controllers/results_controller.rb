class ResultsController < ApplicationController
  def index
    @results = CrawlResult.with_task_and_campaign.recent

    if params[:search].present?
      @results = @results.search_by_data(params[:search])
    end

    @results = @results.page(params[:page])
  end

  def show
    @result = CrawlResult.with_task_and_campaign.find(params[:id])
  end
end
