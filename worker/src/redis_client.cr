require "redis"
require "log"

module Kalubampa
  class RedisClient
    Log = ::Log.for(self)

    TASK_QUEUE        = "kalubampa:task_queue"
    PROCESSING_QUEUE  = "kalubampa:processing_queue"
    RESULT_QUEUE      = "kalubampa:result_queue"
    DEAD_LETTER_QUEUE = "kalubampa:dead_letter_queue"
    RETRY_COUNTER_KEY = "kalubampa:retry_counts"
    STATS_KEY         = "kalubampa:worker_stats"

    BLOCK_TIMEOUT = 5

    getter redis : Redis
    property max_retries : Int32
    property dead_letter_enabled : Bool
    property worker_id : String

    def initialize(
      redis_url : String = "redis://localhost:6379",
      max_retries : Int32 = 3,
      dead_letter_enabled : Bool = true,
      worker_id : String = "worker-unknown"
    )
      @max_retries = max_retries
      @dead_letter_enabled = dead_letter_enabled
      @worker_id = worker_id
      @redis = connect_with_retry(redis_url)
    end

    private def connect_with_retry(redis_url : String, attempts : Int32 = 5) : Redis
      attempt = 0
      loop do
        attempt += 1
        begin
          redis = Redis.new(url: redis_url)
          redis.ping
          Log.info { "✅ Redis terkoneksi: #{redis_url}" }
          return redis
        rescue ex : Exception
          if attempt >= attempts
            Log.error { "❌ Gagal koneksi Redis setelah #{attempts} percobaan: #{ex.message}" }
            raise ex
          end
          delay = (2 ** attempt).seconds
          Log.warn { "⏳ Redis koneksi gagal (#{attempt}/#{attempts}), retry dalam #{delay}..." }
          sleep delay
        end
      end
    end

    def fetch_task : String?
      result = @redis.brpoplpush(
        TASK_QUEUE,
        PROCESSING_QUEUE,
        BLOCK_TIMEOUT
      )
      result.as?(String)
    rescue ex : Exception
      Log.error { "❌ Redis fetch_task error: #{ex.message}" }
      sleep 1.seconds # Hindari tight loop saat Redis down
      nil
    end

    def acknowledge_task(task : String)
      @redis.lrem(PROCESSING_QUEUE, 1, task)
      @redis.hdel(RETRY_COUNTER_KEY, task)
      increment_stat("tasks_completed")
    rescue ex : Exception
      Log.error { "❌ Redis acknowledge error: #{ex.message}" }
    end

    def requeue_task(task : String)
      retry_count = get_retry_count(task)

      if retry_count >= @max_retries
        if @dead_letter_enabled
          move_to_dead_letter(task, retry_count)
        else
          @redis.lrem(PROCESSING_QUEUE, 1, task)
          @redis.hdel(RETRY_COUNTER_KEY, task)
          Log.warn { "🗑️  Task dibuang (max retries exceeded): #{task}" }
        end
        increment_stat("tasks_failed_permanent")
      else
        @redis.lrem(PROCESSING_QUEUE, 1, task)
        @redis.lpush(TASK_QUEUE, task)
        @redis.hincrby(RETRY_COUNTER_KEY, task, 1)
        increment_stat("tasks_requeued")
        Log.info { "🔄 Task di-requeue (#{retry_count + 1}/#{@max_retries}): #{task}" }
      end
    rescue ex : Exception
      Log.error { "❌ Redis requeue error: #{ex.message}" }
    end

    def push_result(json_data : String)
      @redis.rpush(RESULT_QUEUE, json_data)
      increment_stat("results_pushed")
    rescue ex : Exception
      Log.error { "❌ Redis push_result error: #{ex.message}" }
    end

    def push_results(json_items : Array(String))
      return if json_items.empty?
      @redis.rpush(RESULT_QUEUE, json_items.map(&.as(Redis::RedisValue)))
      increment_stat_by("results_pushed", json_items.size)
    rescue ex : Exception
      Log.error { "❌ Redis push_results batch error: #{ex.message}" }
    end

    private def move_to_dead_letter(task : String, retry_count : Int32)
      dead_letter_entry = %({"task":#{task},"retries":#{retry_count},"worker":"#{@worker_id}","failed_at":"#{Time.utc.to_rfc3339}"})

      @redis.lrem(PROCESSING_QUEUE, 1, task)
      @redis.rpush(DEAD_LETTER_QUEUE, dead_letter_entry)
      @redis.hdel(RETRY_COUNTER_KEY, task)

      Log.warn { "💀 Task dipindahkan ke Dead Letter Queue (#{retry_count} retries): #{task}" }
    end

    private def get_retry_count(task : String) : Int32
      result = @redis.hget(RETRY_COUNTER_KEY, task)
      result.try(&.to_i) || 0
    rescue
      0
    end

    def recover_stale_tasks(max_age_seconds : Int32 = 300) : Int32
      stale_count = @redis.llen(PROCESSING_QUEUE)
      return 0 if stale_count == 0

      Log.info { "🔍 Ditemukan #{stale_count} task di processing_queue, memulihkan..." }

      recovered = 0
      stale_count.times do
        task = @redis.rpoplpush(PROCESSING_QUEUE, TASK_QUEUE)
        break unless task
        recovered += 1
      end

      Log.info { "♻️  #{recovered} stale tasks dipulihkan ke task_queue" }
      increment_stat_by("tasks_recovered", recovered)
      recovered
    end

    def queue_stats : NamedTuple(
      tasks: Int64,
      processing: Int64,
      results: Int64,
      dead_letter: Int64
    )
      {
        tasks:       @redis.llen(TASK_QUEUE),
        processing:  @redis.llen(PROCESSING_QUEUE),
        results:     @redis.llen(RESULT_QUEUE),
        dead_letter: @redis.llen(DEAD_LETTER_QUEUE),
      }
    end

    private def increment_stat(field : String)
      @redis.hincrby("#{STATS_KEY}:#{@worker_id}", field, 1)
    rescue
      # Stats bersifat best-effort, jangan crash
    end

    private def increment_stat_by(field : String, amount : Int32)
      @redis.hincrby("#{STATS_KEY}:#{@worker_id}", field, amount)
    rescue
    end

    def worker_stats : Hash(String, String)
      result = @redis.hgetall("#{STATS_KEY}:#{@worker_id}")
      hash = Hash(String, String).new
      result.each_slice(2) do |pair|
        key = pair[0].as(String)
        value = pair[1].as(String)
        hash[key] = value
      end
      hash
    rescue
      Hash(String, String).new
    end

    def ping : Bool
      @redis.ping == "PONG"
    rescue
      false
    end

    def close
      Log.info { "🔌 Redis connection closing..." }
      @redis.close
    rescue
    end
  end
end
