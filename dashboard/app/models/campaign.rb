class Campaign < ApplicationRecord
  has_many :crawl_tasks, dependent: :destroy
  has_many :crawl_results, through: :crawl_tasks

  validates :name, presence: true, length: { maximum: 255 }
  validates :status, presence: true,
    inclusion: { in: %w[draft active paused completed failed] }
  validate :validate_extraction_schema_json

  scope :with_stats, -> {
    select(
      "campaigns.*",
      "(SELECT COUNT(*) FROM crawl_tasks WHERE crawl_tasks.campaign_id = campaigns.id) AS tasks_count_cache",
      "(SELECT COUNT(*) FROM crawl_tasks WHERE crawl_tasks.campaign_id = campaigns.id AND crawl_tasks.status = 'completed') AS completed_tasks_count",
      "(SELECT COUNT(*) FROM crawl_results INNER JOIN crawl_tasks ON crawl_results.crawl_task_id = crawl_tasks.id WHERE crawl_tasks.campaign_id = campaigns.id) AS results_count_cache"
    )
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: "active") }

  after_initialize :set_defaults, if: :new_record?

  def dispatch_tasks!
    TaskDispatcherService.call(self)
  end

  def progress_percentage
    total = respond_to?(:tasks_count_cache) ? tasks_count_cache : crawl_tasks.count
    return 0 if total.zero?
    completed = respond_to?(:completed_tasks_count) ? completed_tasks_count : crawl_tasks.where(status: "completed").count
    ((completed.to_f / total) * 100).round(1)
  end

  def extraction_schema=(value)
    parsed = value.is_a?(String) ? (JSON.parse(value) rescue value) : value
    super(parsed)
  end

  private

  def set_defaults
    self.status ||= "draft"
    self.extraction_schema ||= {}
  end

  def validate_extraction_schema_json
    return if extraction_schema.is_a?(Hash)
    errors.add(:extraction_schema, "must be valid JSON")
  end
end
