class TaskDispatcherService
  def self.call(campaign)
    new(campaign).call
  end

  def initialize(campaign)
    @campaign = campaign
  end

  def call
    return unless @campaign.status == "active"

    pending_tasks = @campaign.crawl_tasks.where(status: "pending")
    return if pending_tasks.empty?

    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))

    pending_tasks.find_each(batch_size: 500) do |task|
      payload = {
        url: task.target_url,
        schema_json: @campaign.extraction_schema
      }.to_json

      redis.lpush("kalubampa:task_queue", payload)
    end

    pending_tasks.update_all(status: "queued")
    redis.close
    @campaign.update!(dispatched_at: Time.current)
  end
end
