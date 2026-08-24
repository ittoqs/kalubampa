
class CreateCrawlResults < ActiveRecord::Migration[7.1]
  def change
    create_table :crawl_results do |t|
      t.references :crawl_task,  null: false, foreign_key: true
      t.string     :title,       null: false
      t.string     :price
      t.text       :description
      t.string     :image_url
      t.string     :extracted_url

      t.timestamps
    end

    add_index :crawl_results, :title
    add_index :crawl_results, :created_at
  end
end
