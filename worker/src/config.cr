module Kalubampa
  class Config
    getter redis_url : String
    getter redis_pool_size : Int32

    getter http_concurrency : Int32
    getter http_connect_timeout : Int32
    getter http_read_timeout : Int32
    getter http_max_retries : Int32
    getter http_retry_delay_ms : Int32
    getter user_agent : String

    getter worker_id : String
    getter batch_size : Int32
    getter stats_interval : Int32
    getter max_requeue_count : Int32

    getter dead_letter_enabled : Bool

    def initialize
      @redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379")
      @redis_pool_size = ENV.fetch("REDIS_POOL_SIZE", "3").to_i

      @http_concurrency = ENV.fetch("HTTP_CONCURRENCY", "50").to_i
      @http_connect_timeout = ENV.fetch("HTTP_CONNECT_TIMEOUT", "10").to_i
      @http_read_timeout = ENV.fetch("HTTP_READ_TIMEOUT", "30").to_i
      @http_max_retries = ENV.fetch("HTTP_MAX_RETRIES", "2").to_i
      @http_retry_delay_ms = ENV.fetch("HTTP_RETRY_DELAY_MS", "500").to_i
      @user_agent = ENV.fetch(
        "USER_AGENT",
        "Kalubampa-Crawler/0.2.0 (+https://kalubampa.dev/bot)"
      )

      @worker_id = ENV.fetch("WORKER_ID", "worker-#{Random::Secure.hex(4)}")
      @batch_size = ENV.fetch("BATCH_SIZE", "10").to_i
      @stats_interval = ENV.fetch("STATS_INTERVAL", "30").to_i
      @max_requeue_count = ENV.fetch("MAX_REQUEUE_COUNT", "3").to_i

      @dead_letter_enabled = ENV.fetch("DEAD_LETTER_ENABLED", "true") == "true"
    end

    def to_s(io : IO) : Nil
      io << "Kalubampa Config:\n"
      io << "  Worker ID:        #{@worker_id}\n"
      io << "  Redis URL:        #{@redis_url}\n"
      io << "  HTTP Concurrency: #{@http_concurrency}\n"
      io << "  Batch Size:       #{@batch_size}\n"
      io << "  Max Retries:      #{@http_max_retries}\n"
      io << "  Dead Letter:      #{@dead_letter_enabled}\n"
    end
  end
end
