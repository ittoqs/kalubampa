
class ApplicationController < ActionController::Base
  http_basic_authenticate_with(
    name: ENV.fetch("ADMIN_USERNAME", "admin"),
    password: ENV.fetch("ADMIN_PASSWORD") { raise "ADMIN_PASSWORD env var required" }
  )

  helper_method :queue_stats

  private

  def queue_stats
    @_queue_stats ||= Sidekiq.redis do |redis|
      {
        tasks:       redis.llen("kalubampa:task_queue"),
        processing:  redis.llen("kalubampa:processing_queue"),
        results:     redis.llen("kalubampa:result_queue"),
        dead_letter: redis.llen("kalubampa:dead_letter_queue")
      }
    end
  rescue
    { tasks: 0, processing: 0, results: 0, dead_letter: 0 }
  end
end
