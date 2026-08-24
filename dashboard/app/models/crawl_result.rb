class CrawlResult < ApplicationRecord
  belongs_to :crawl_task

  scope :with_task_and_campaign, -> {
    includes(crawl_task: :campaign)
  }
  scope :recent, -> { order(created_at: :desc) }

  scope :search_by_data, ->(query) {
    where("extracted_data::text ILIKE ?", "%#{sanitize_sql_like(query)}%")
  }

  delegate :target_url, to: :crawl_task, allow_nil: true
  delegate :campaign, to: :crawl_task, allow_nil: true

  def data_field(key)
    extracted_data.is_a?(Hash) ? extracted_data[key.to_s] : nil
  end

  def data_field_present?(key)
    val = data_field(key)
    val.present? && val != "N/A"
  end
end
