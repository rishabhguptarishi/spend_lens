# frozen_string_literal: true

# Phase 6 §G14 — denormalize user_id onto transactions.
#
# Before this migration, user-scoping went through `statement.bank_account.user_id`
# (a 3-table chain). That's correct but slow on every page that asks
# "all of THIS user's transactions" and fragile when we want
# DB-level constraints / RLS later.
#
# Migration is split:
#   - This file adds the column NULLABLE and backfills from the join chain.
#   - A follow-up post-deploy migration enforces NOT NULL once the app code
#     starts writing user_id on every Transaction insert.
#
# Doing it in one migration is risky: until every writer is updated, a
# NOT NULL constraint would crash incoming uploads. Two-step is safer
# even though the column briefly allows NULLs.
class AddUserIdToTransactions < ActiveRecord::Migration[8.0]
  def up
    add_reference :transactions, :user, foreign_key: true, null: true, index: true

    execute <<~SQL
      UPDATE transactions
      SET user_id = bank_accounts.user_id
      FROM statements
      JOIN bank_accounts ON bank_accounts.id = statements.bank_account_id
      WHERE transactions.statement_id = statements.id
        AND transactions.user_id IS NULL
    SQL
  end

  def down
    remove_reference :transactions, :user, foreign_key: true
  end
end
