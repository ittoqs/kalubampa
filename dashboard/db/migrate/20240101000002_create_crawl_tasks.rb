
class CreateCrawlTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :crawl_tasks do |t|
      t.references :campaign,     null: false, foreign_key: true
      t.string     :target_url,   null: false
      t.string     :status,       null: false, default: "pending"
      t.text       :error_message
      t.datetime   :completed_at

      t.timestamps
    end

    add_index :crawl_tasks, :status
    add_index :crawl_tasks, :target_url
    add_index :crawl_tasks, [:campaign_id, :status]
  end
end
