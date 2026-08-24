
class DashboardController < ApplicationController
  def index
    @stats = {
      total_campaigns:   Campaign.count,
      active_campaigns:  Campaign.active.count,
      total_tasks:       CrawlTask.count,
      completed_tasks:   CrawlTask.completed.count,
      failed_tasks:      CrawlTask.failed.count,
      total_results:     CrawlResult.count,
      recent_results:    CrawlResult.recent.limit(10).includes(crawl_task: :campaign)
    }
    @recent_campaigns = Campaign.with_stats.recent.limit(5)
  end
end
