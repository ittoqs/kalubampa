class TaskDispatcherJob < ApplicationJob
  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find(campaign_id)
    campaign.dispatch_tasks!
  end
end
