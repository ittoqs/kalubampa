class ResultCollectorJob < ApplicationJob
  queue_as :critical

  BATCH_SIZE = 100
  RESULT_QUEUE = "kalubampa:result_queue"

  def perform
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    collected = 0

    loop do
      raw_results = fetch_batch(redis, BATCH_SIZE)
      break if raw_results.empty?

      parsed_results = parse_results(raw_results)
      next if parsed_results.empty?

      inserted_count = bulk_insert_results(parsed_results)
      collected += inserted_count

      Rails.logger.info(
        "[ResultCollector] Batch inserted: #{inserted_count} results " \
        "(total cycle: #{collected})"
      )

      break if raw_results.size < BATCH_SIZE
    end

    Rails.logger.info("[ResultCollector] Cycle complete: #{collected} results saved")
    redis.close
  rescue => e
    Rails.logger.error("[ResultCollector] Error: #{e.message}")
    raise
  end

  private

  def fetch_batch(redis, batch_size)
    results = redis.pipelined do |pipe|
      batch_size.times { pipe.lpop(RESULT_QUEUE) }
    end
    results.compact.map(&:to_s)
  end

  def parse_results(raw_results)
    raw_results.filter_map do |raw|
      JSON.parse(raw)
    rescue JSON::ParserError => e
      Rails.logger.warn("[ResultCollector] JSON parse error: #{e.message}")
      nil
    end
  end

  def bulk_insert_results(parsed_results)
    now = Time.current

    urls = parsed_results.map { |r| r["task_url"] }.compact
    task_map = CrawlTask
      .where(target_url: urls, status: %w[queued processing])
      .index_by(&:target_url)

    records = parsed_results.flat_map do |result|
      task = task_map[result["task_url"]]

      unless task
        task = CrawlTask
          .where(status: %w[queued processing])
          .order(:created_at)
          .first
      end

      next [] unless task

      data_entries = result["data"].is_a?(Array) ? result["data"] : [result["data"]]

      data_entries.map do |data_entry|
        {
          crawl_task_id:  task.id,
          extracted_data: data_entry,
          created_at:     now,
          updated_at:     now
        }
      end
    end.compact

    return 0 if records.empty?

    CrawlResult.insert_all(records)

    task_ids = records.map { |r| r[:crawl_task_id] }.uniq
    CrawlTask.where(id: task_ids).update_all(
      status: "completed",
      completed_at: now
    )

    check_campaign_completion(task_ids)

    records.size
  end

  def check_campaign_completion(task_ids)
    campaign_ids = CrawlTask.where(id: task_ids).distinct.pluck(:campaign_id)

    campaign_ids.each do |campaign_id|
      campaign = Campaign.find(campaign_id)
      pending = campaign.crawl_tasks.where.not(status: %w[completed failed]).count

      if pending.zero?
        campaign.update!(status: "completed", completed_at: Time.current)
        Rails.logger.info("[ResultCollector] Campaign ##{campaign_id} completed!")
      end
    end
  end
end
