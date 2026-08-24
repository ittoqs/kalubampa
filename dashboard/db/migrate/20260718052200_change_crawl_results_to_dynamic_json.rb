class ChangeCrawlResultsToDynamicJson < ActiveRecord::Migration[7.1]
  def change
    remove_index :crawl_results, :title

    remove_column :crawl_results, :title, :string
    remove_column :crawl_results, :price, :string
    remove_column :crawl_results, :description, :text
    remove_column :crawl_results, :image_url, :string
    remove_column :crawl_results, :extracted_url, :string

    add_column :crawl_results, :extracted_data, :jsonb, default: {}, null: false
    
    add_index :crawl_results, :extracted_data, using: :gin

    add_column :campaigns, :extraction_schema, :jsonb, default: {}, null: false
  end
end
