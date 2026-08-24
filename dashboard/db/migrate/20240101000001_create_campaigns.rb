
class CreateCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :campaigns do |t|
      t.string  :name,          null: false
      t.text    :description
      t.string  :status,        null: false, default: "draft"
      t.datetime :dispatched_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :campaigns, :status
    add_index :campaigns, :created_at
  end
end
