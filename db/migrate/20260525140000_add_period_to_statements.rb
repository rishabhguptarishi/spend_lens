# frozen_string_literal: true

class AddPeriodToStatements < ActiveRecord::Migration[8.0]
  def up
    add_column :statements, :period_start, :date
    add_column :statements, :period_end, :date
    add_index :statements, %i[bank_account_id period_start period_end],
              name: "index_statements_on_bank_account_period"

    # Backfill: prefer actual transaction min/max dates, fall back to month/year.
    say_with_time "Backfilling period_start/period_end on existing statements" do
      Statement.reset_column_information
      Statement.find_each do |stmt|
        tx_range = stmt.transactions.where.not(date: nil).pluck("MIN(date), MAX(date)").first
        if tx_range && tx_range[0].present?
          stmt.update_columns(period_start: tx_range[0], period_end: tx_range[1])
          next
        end

        if stmt.month.present? && stmt.year.present?
          first = Date.new(stmt.year, stmt.month, 1)
          stmt.update_columns(period_start: first, period_end: first.end_of_month)
        end
      end
    end
  end

  def down
    remove_index :statements, name: "index_statements_on_bank_account_period"
    remove_column :statements, :period_end
    remove_column :statements, :period_start
  end
end
