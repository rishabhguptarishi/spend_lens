# frozen_string_literal: true

# Phase 6 §G16 — content-addressable upload dedup.
#
# Closes the "double-click upload" race: two simultaneous POSTs to
# /upload with the same file create two Statement rows → two parses →
# duplicated transactions.
#
# The fix: compute SHA-256 of the file content at upload time, store it
# on the Statement, and add a unique index on (bank_account_id,
# file_sha). The second concurrent request hits the unique constraint
# and the controller catches RecordNotUnique → redirects to the
# already-created statement.
#
# The index is PARTIAL (where file_sha IS NOT NULL) so legacy statements
# uploaded before this column existed remain valid.
class AddFileShaToStatements < ActiveRecord::Migration[8.0]
  def change
    add_column :statements, :file_sha, :string

    add_index :statements, %i[bank_account_id file_sha],
      unique: true,
      where: 'file_sha IS NOT NULL',
      name: 'index_statements_on_bank_account_and_file_sha'
  end
end
