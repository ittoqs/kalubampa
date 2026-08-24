require "log"
require "json"
require "./config"
require "./redis_client"
require "./fetcher"
require "./ffi_bindings"

Log.setup do |c|
  backend = Log::IOBackend.new(formatter: Log::ShortFormat)
  c.bind("*", :info, backend)
  c.bind("kalubampa.*", :debug, backend)
end

module Kalubampa
  struct TaskPayload
    include JSON::Serializable
    property url : String
    property schema_json : JSON::Any?
  end

  class Worker
    Log = ::Log.for(self)

    getter config : Config
    getter redis : RedisClient
    getter fetcher : Fetcher
    getter running : Bool
    getter in_flight : Atomic(Int32)
    getter total_processed : Atomic(Int64)
    getter total_failed : Atomic(Int64)

    def initialize(@config : Config)
      @redis = RedisClient.new(
        redis_url: @config.redis_url,
        max_retries: @config.max_requeue_count,
        dead_letter_enabled: @config.dead_letter_enabled,
        worker_id: @config.worker_id
      )
      @fetcher = Fetcher.new(@config)
      @running = true
      @in_flight = Atomic(Int32).new(0)
      @total_processed = Atomic(Int64).new(0)
      @total_failed = Atomic(Int64).new(0)

      Signal::INT.trap { graceful_shutdown }
      Signal::TERM.trap { graceful_shutdown }
    end

    def run
      print_banner
      startup_checks
      start_stats_reporter

      Log.info { "📡 Mendengarkan antrean: #{RedisClient::TASK_QUEUE}" }
      Log.info { "⚡ Mode: batch (#{@config.batch_size} tasks/cycle, #{@config.http_concurrency} concurrent)" }

      while @running
        process_batch
      end

      wait_for_in_flight

      Log.info { "📊 Total diproses: #{@total_processed.get}, gagal: #{@total_failed.get}" }
      Log.info { "👋 Kalubampa Worker [#{@config.worker_id}] berhenti." }
      @redis.close
    end

    private def process_batch
      raw_tasks = collect_tasks(@config.batch_size)
      return if raw_tasks.empty?

      Log.info { "📥 Batch diterima: #{raw_tasks.size} tasks" }
      @in_flight.add(raw_tasks.size)

      begin
        url_to_schema = {} of String => String
        url_to_raw = {} of String => String
        urls_to_fetch = [] of String

        raw_tasks.each do |raw_str|
          begin
            if raw_str.starts_with?("{")
              payload = TaskPayload.from_json(raw_str)
              schema = payload.schema_json ? payload.schema_json.to_json : "{}"
              url_to_schema[payload.url] = schema
              url_to_raw[payload.url] = raw_str
              urls_to_fetch << payload.url
            else
              # Backward compatibility for plain URLs
              url_to_schema[raw_str] = "{}"
              url_to_raw[raw_str] = raw_str
              urls_to_fetch << raw_str
            end
          rescue ex : JSON::ParseException
            Log.warn { "⚠️  Gagal parse task payload JSON: #{ex.message} - #{raw_str}" }
            @total_failed.add(1)
            @redis.acknowledge_task(raw_str)
          end
        end

        fetch_results = @fetcher.fetch_batch(urls_to_fetch)
        results_to_push = [] of String

        fetch_results.each do |fetch_result|
          task_url = fetch_result.url
          raw_str = url_to_raw[task_url]
          schema_str = url_to_schema[task_url]

          if html = fetch_result.html
            Log.debug { "📄 HTML diunduh: #{fetch_result.bytes} bytes (#{fetch_result.duration_ms}ms) — #{task_url}" }

            extracted_json = Kalubampa::Extractor.extract(html, schema_str)

            if extracted_json
              Log.debug { "🔍 Ekstraksi berhasil: #{task_url}" }

              begin
                payload = {
                  "task_url" => task_url,
                  "data"     => JSON.parse(extracted_json),
                }.to_json
                results_to_push << payload
                @redis.acknowledge_task(raw_str)
                @total_processed.add(1)
              rescue ex : JSON::ParseException
                Log.error { "❌ Invalid JSON dari Rust: #{ex.message}" }
                @redis.requeue_task(raw_str)
                @total_failed.add(1)
              end
            else
              Log.warn { "⚠️  Ekstraksi gagal (null result): #{task_url}" }
              @redis.acknowledge_task(raw_str)
              @total_failed.add(1)
            end
          else
            Log.warn { "⚠️  Fetch gagal: #{task_url} — #{fetch_result.error}" }
            @redis.requeue_task(raw_str)
            @total_failed.add(1)
          end
        end

        unless results_to_push.empty?
          @redis.push_results(results_to_push)
          Log.info { "✅ Batch selesai: #{results_to_push.size} hasil dikirim ke result_queue" }
        end

      rescue ex : Exception
        Log.error { "❌ Error batch processing: #{ex.message}" }
        raw_tasks.each { |t| @redis.requeue_task(t) }
      ensure
        @in_flight.sub(raw_tasks.size)
      end
    end

    private def collect_tasks(max : Int32) : Array(String)
      tasks = [] of String

      first = @redis.fetch_task
      return tasks unless first
      tasks << first

      (max - 1).times do
        break unless @running
        begin
          next_task = @redis.redis.rpoplpush(
            RedisClient::TASK_QUEUE,
            RedisClient::PROCESSING_QUEUE
          )
          if task_str = next_task.as?(String)
            tasks << task_str
          else
            break
          end
        rescue
          break
        end
      end

      tasks
    end

    private def print_banner
      Log.info { "" }
      Log.info { "  🕷️  ╔═══════════════════════════════════════════════╗" }
      Log.info { "     ║   Kalubampa Worker v0.2.0                    ║" }
      Log.info { "     ║   High-Performance Polyglot Web Crawler      ║" }
      Log.info { "     ╚═══════════════════════════════════════════════╝" }
      Log.info { "" }
      Log.info { "  Worker ID: #{@config.worker_id}" }
      Log.info { "" }
    end

    private def startup_checks
      unless @redis.ping
        Log.error { "❌ Redis tidak responsif!" }
        raise "Redis connection failed"
      end

      begin
        version_ptr = LibRustParser.parser_version
        if version_ptr.null?
          Log.error { "❌ Rust Parser tidak tersedia (NULL version)" }
          raise "Rust Parser unavailable"
        end
        version = String.new(version_ptr)
        LibRustParser.free_json_string(version_ptr)
        Log.info { "🛡️  Rust Parser: #{version}" }
      rescue ex : Exception
        Log.error { "❌ Rust Parser FFI error: #{ex.message}" }
        raise "Rust Parser FFI failed: #{ex.message}"
      end

      recovered = @redis.recover_stale_tasks
      Log.info { "♻️  Stale tasks recovered: #{recovered}" } if recovered > 0

      stats = @redis.queue_stats
      Log.info { "📊 Queue stats — Tasks: #{stats[:tasks]}, Processing: #{stats[:processing]}, Results: #{stats[:results]}, Dead Letter: #{stats[:dead_letter]}" }
    end

    private def start_stats_reporter
      spawn do
        while @running
          sleep @config.stats_interval.seconds
          report_stats if @running
        end
      end
    end

    private def report_stats
      stats = @redis.queue_stats
      Log.info {
        "📊 [#{@config.worker_id}] " \
        "Processed: #{@total_processed.get} | " \
        "Failed: #{@total_failed.get} | " \
        "In-flight: #{@in_flight.get} | " \
        "Queue: #{stats[:tasks]} | " \
        "Results: #{stats[:results]} | " \
        "Dead: #{stats[:dead_letter]}"
      }
    end

    private def graceful_shutdown
      Log.info { "🛑 Sinyal shutdown diterima..." }
      @running = false
    end

    private def wait_for_in_flight
      if @in_flight.get > 0
        Log.info { "⏳ Menunggu #{@in_flight.get} in-flight tasks selesai..." }
        60.times do
          break if @in_flight.get == 0
          sleep 1.second
        end
        if @in_flight.get > 0
          Log.warn { "⚠️  #{@in_flight.get} tasks masih in-flight saat shutdown" }
        end
      end
    end
  end
end

config = Kalubampa::Config.new
worker = Kalubampa::Worker.new(config)
worker.run
