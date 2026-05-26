# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_26_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bank_accounts", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.string "bank_name"
    t.string "account_type"
    t.string "last_four"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_bank_accounts_on_user_id"
  end

  create_table "budgets", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "category_id", null: false
    t.decimal "amount"
    t.integer "month"
    t.integer "year"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_budgets_on_category_id"
    t.index ["user_id"], name: "index_budgets_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name"
    t.string "color"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "category_rules", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "merchant_pattern", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_category_rules_on_category_id"
    t.index ["user_id", "merchant_pattern"], name: "index_category_rules_on_user_id_and_merchant_pattern"
    t.index ["user_id"], name: "index_category_rules_on_user_id"
  end

  create_table "credit_cards", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "bank_name"
    t.string "card_type"
    t.decimal "annual_fee", precision: 10, scale: 2, default: "0.0"
    t.decimal "fee_waiver_spend", precision: 10, scale: 2
    t.jsonb "rewards_structure", default: {}
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
  end

  create_table "investment_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "provider"
    t.string "account_kind", default: "other", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_investment_accounts_on_user_id"
  end

  create_table "investment_holdings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "investment_account_id", null: false
    t.string "asset_class", null: false
    t.string "name", null: false
    t.string "symbol"
    t.string "folio"
    t.decimal "units", precision: 18, scale: 6, default: "0.0"
    t.decimal "avg_cost", precision: 14, scale: 2, default: "0.0"
    t.decimal "invested_amount", precision: 14, scale: 2, default: "0.0"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investment_account_id"], name: "index_investment_holdings_on_investment_account_id"
    t.index ["user_id"], name: "index_investment_holdings_on_user_id"
  end

  create_table "investment_import_batches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "investment_account_id"
    t.string "source", null: false
    t.string "status", default: "preview", null: false
    t.integer "financial_year_start", null: false
    t.jsonb "preview_rows", default: []
    t.jsonb "column_mapping", default: {}
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investment_account_id"], name: "index_investment_import_batches_on_investment_account_id"
    t.index ["user_id", "status"], name: "index_investment_import_batches_on_user_id_and_status"
    t.index ["user_id"], name: "index_investment_import_batches_on_user_id"
  end

  create_table "investment_suggestions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "transaction_id", null: false
    t.string "suggested_asset_class", null: false
    t.string "suggested_kind", null: false
    t.string "suggested_account_name"
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["transaction_id"], name: "index_investment_suggestions_on_transaction_id", unique: true
    t.index ["user_id", "status"], name: "index_investment_suggestions_on_user_id_and_status"
    t.index ["user_id"], name: "index_investment_suggestions_on_user_id"
  end

  create_table "investment_transactions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "investment_account_id"
    t.bigint "investment_holding_id"
    t.bigint "transaction_id"
    t.date "date", null: false
    t.string "kind", null: false
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.decimal "units", precision: 18, scale: 6
    t.string "description"
    t.string "source", default: "manual", null: false
    t.integer "financial_year_start", null: false
    t.string "asset_class"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["investment_account_id"], name: "index_investment_transactions_on_investment_account_id"
    t.index ["investment_holding_id"], name: "index_investment_transactions_on_investment_holding_id"
    t.index ["transaction_id"], name: "index_investment_transactions_on_transaction_id"
    t.index ["user_id", "date"], name: "index_investment_transactions_on_user_id_and_date"
    t.index ["user_id", "financial_year_start"], name: "index_inv_txns_on_user_fy"
    t.index ["user_id"], name: "index_investment_transactions_on_user_id"
  end

  create_table "itr_tax_documents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "financial_year_start", null: false
    t.string "document_type", null: false
    t.string "status", default: "uploaded", null: false
    t.jsonb "extracted_data", default: {}
    t.string "extraction_status", default: "pending", null: false
    t.jsonb "confirmed_data", default: {}
    t.datetime "ledger_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payer_name"
    t.string "source_label"
    t.date "period_start"
    t.date "period_end"
    t.string "deduction_section"
    t.index ["ledger_synced_at"], name: "index_itr_tax_documents_on_ledger_synced_at"
    t.index ["user_id", "financial_year_start", "deduction_section"], name: "index_itr_docs_on_user_fy_section"
    t.index ["user_id", "financial_year_start", "document_type"], name: "index_itr_docs_on_user_fy_type"
    t.index ["user_id"], name: "index_itr_tax_documents_on_user_id"
  end

  create_table "statements", force: :cascade do |t|
    t.integer "bank_account_id", null: false
    t.integer "month"
    t.integer "year"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "period_start"
    t.date "period_end"
    t.index ["bank_account_id", "month", "year"], name: "index_statements_on_bank_account_month_year"
    t.index ["bank_account_id", "period_start", "period_end"], name: "index_statements_on_bank_account_period"
    t.index ["bank_account_id"], name: "index_statements_on_bank_account_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "statement_id", null: false
    t.integer "category_id"
    t.date "date"
    t.string "description"
    t.decimal "amount"
    t.string "transaction_type"
    t.string "merchant"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_recurring", default: false
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["date", "transaction_type"], name: "index_transactions_on_date_and_type"
    t.index ["statement_id", "date"], name: "index_transactions_on_statement_id_and_date"
    t.index ["statement_id"], name: "index_transactions_on_statement_id"
  end

  create_table "user_investment_detection_rules", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "pattern", null: false
    t.string "asset_class", null: false
    t.string "kind", null: false
    t.string "account_name", null: false
    t.string "account_kind"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "pattern"], name: "index_user_investment_detection_rules_on_user_id_and_pattern", unique: true
    t.index ["user_id"], name: "index_user_investment_detection_rules_on_user_id"
  end

  create_table "user_notification_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.boolean "monthly_digest", default: true, null: false
    t.boolean "investment_suggestions", default: true, null: false
    t.boolean "itr_season_reminders", default: true, null: false
    t.boolean "budget_alerts", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_user_notification_preferences_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.jsonb "preferences", default: {}, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bank_accounts", "users"
  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "category_rules", "categories"
  add_foreign_key "category_rules", "users"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "investment_accounts", "users"
  add_foreign_key "investment_holdings", "investment_accounts"
  add_foreign_key "investment_holdings", "users"
  add_foreign_key "investment_import_batches", "investment_accounts"
  add_foreign_key "investment_import_batches", "users"
  add_foreign_key "investment_suggestions", "transactions"
  add_foreign_key "investment_suggestions", "users"
  add_foreign_key "investment_transactions", "investment_accounts"
  add_foreign_key "investment_transactions", "investment_holdings"
  add_foreign_key "investment_transactions", "transactions"
  add_foreign_key "investment_transactions", "users"
  add_foreign_key "itr_tax_documents", "users"
  add_foreign_key "statements", "bank_accounts"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "statements"
  add_foreign_key "user_investment_detection_rules", "users"
  add_foreign_key "user_notification_preferences", "users"
end
