class ApplicationJob < ActiveJob::Base
  self.queue_adapter = :sidekiq

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
end
