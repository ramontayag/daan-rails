class AddVisibleToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :visible, :boolean, default: true, null: false
  end
end
