class CrawlTask < ApplicationRecord
  belongs_to :campaign
  has_many :crawl_results, dependent: :destroy

  validates :target_url, presence: true,
    format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
              message: "harus berupa URL valid (http/https)" }
  validates :status, presence: true,
    inclusion: { in: %w[pending queued processing completed failed] }

  scope :with_results, -> { includes(:crawl_results) }
  scope :pending, -> { where(status: "pending") }
  scope :queued, -> { where(status: "queued") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  after_initialize :set_defaults, if: :new_record?

  def mark_completed!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_failed!(error_message = nil)
    update!(status: "failed", error_message: error_message)
  end

  private

  def set_defaults
    self.status ||= "pending"
  end
end
