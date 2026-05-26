# frozen_string_literal: true

class UserSettingsPhase1Phase2 < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :preferences, :jsonb, null: false, default: {}

    create_table :user_notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :monthly_digest, null: false, default: true
      t.boolean :investment_suggestions, null: false, default: true
      t.boolean :itr_season_reminders, null: false, default: true
      t.boolean :budget_alerts, null: false, default: true
      t.timestamps
    end

    create_table :user_investment_detection_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :pattern, null: false
      t.string :asset_class, null: false
      t.string :kind, null: false
      t.string :account_name, null: false
      t.string :account_kind
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :user_investment_detection_rules, %i[user_id pattern], unique: true

    reversible do |dir|
      dir.up do
        say_with_time 'Backfill notification preferences' do
          User.find_each do |user|
            next if UserNotificationPreference.exists?(user_id: user.id)

            UserNotificationPreference.create!(user: user)
          end
        end
      end
    end
  end
end
