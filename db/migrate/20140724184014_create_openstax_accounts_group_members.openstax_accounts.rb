# This migration comes from openstax_accounts (originally 2)
class CreateOpenStaxAccountsGroupMembers < ActiveRecord::Migration
  def change
    create_table :openstax_accounts_group_members do |t|
      t.references :group, null: false
      t.references :user, null: false

      t.timestamps null: false

      t.index [:group_id, :user_id], unique: true
      t.index :user_id
    end
  end
end
