Sidekiq.configure_server do |config|
  config.redis = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379"),
    network_timeout: 5,
    pool_timeout: 5
  }

  config.on(:startup) do
    Sidekiq::Cron::Job.create(
      name: "ResultCollector - every 30 seconds",
      cron: "* * * * *",
      class: "ResultCollectorJob",
      queue: "critical"
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379"),
    network_timeout: 5,
    pool_timeout: 5
  }
end
