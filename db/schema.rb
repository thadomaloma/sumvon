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

ActiveRecord::Schema[8.1].define(version: 2026_10_05_120000) do
  create_table "account_reconciliations", force: :cascade do |t|
    t.bigint "adjustment_minor", null: false
    t.datetime "created_at", null: false
    t.bigint "financial_account_id", null: false
    t.string "note", limit: 240
    t.date "reconciled_on", null: false
    t.bigint "statement_balance_minor", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["financial_account_id", "reconciled_on"], name: "idx_on_financial_account_id_reconciled_on_44ee36a222"
    t.index ["financial_account_id"], name: "index_account_reconciliations_on_financial_account_id"
    t.index ["user_id"], name: "index_account_reconciliations_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", limit: 80, null: false
    t.bigint "actor_user_id"
    t.datetime "created_at", null: false
    t.string "ip_digest", limit: 32
    t.json "metadata", default: {}, null: false
    t.string "outcome", limit: 24, default: "success", null: false
    t.string "request_id", limit: 64
    t.string "source", limit: 24, default: "web", null: false
    t.bigint "subject_user_id"
    t.datetime "updated_at", null: false
    t.index ["actor_user_id", "created_at"], name: "index_audit_events_on_actor_user_id_and_created_at"
    t.index ["actor_user_id"], name: "index_audit_events_on_actor_user_id"
    t.index ["created_at", "action"], name: "index_audit_events_on_created_at_and_action"
    t.index ["subject_user_id", "created_at"], name: "index_audit_events_on_subject_user_id_and_created_at"
    t.index ["subject_user_id"], name: "index_audit_events_on_subject_user_id"
    t.check_constraint "outcome IN ('success', 'failure', 'blocked')", name: "audit_events_outcome_check"
    t.check_constraint "source IN ('web', 'system')", name: "audit_events_source_check"
  end

  create_table "budget_categories", force: :cascade do |t|
    t.bigint "budget_id", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.bigint "planned_amount_minor", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_id", "category_id"], name: "index_budget_categories_on_budget_id_and_category_id", unique: true
    t.index ["budget_id"], name: "index_budget_categories_on_budget_id"
    t.index ["category_id"], name: "index_budget_categories_on_category_id"
    t.check_constraint "planned_amount_minor > 0", name: "budget_categories_positive_amount_check"
  end

  create_table "budgets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.integer "month", null: false
    t.bigint "planned_amount_minor", null: false
    t.boolean "rollover_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", null: false
    t.index ["user_id", "year", "month", "currency"], name: "index_budgets_on_user_id_and_year_and_month_and_currency", unique: true
    t.index ["user_id"], name: "index_budgets_on_user_id"
    t.check_constraint "length(currency) = 3", name: "budgets_currency_check"
    t.check_constraint "month >= 1 AND month <= 12", name: "budgets_month_check"
    t.check_constraint "planned_amount_minor >= 0", name: "budgets_nonnegative_amount_check"
    t.check_constraint "year >= 2000 AND year <= 2200", name: "budgets_year_check"
  end

  create_table "categories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "icon", default: "circle", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["kind", "name"], name: "index_default_categories_on_kind_and_name", unique: true, where: "(user_id IS NULL)"
    t.index ["user_id", "kind", "name"], name: "index_categories_on_user_id_and_kind_and_name", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
    t.check_constraint "kind IN ('income', 'expense')", name: "categories_kind_check"
  end

  create_table "financial_accounts", force: :cascade do |t|
    t.string "account_type", null: false
    t.boolean "archived", default: false, null: false
    t.bigint "balance_anchor_transaction_id", default: 0, null: false
    t.date "balance_started_on", default: -> { "CURRENT_DATE" }, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.string "name", null: false
    t.bigint "opening_balance_minor", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "archived"], name: "index_financial_accounts_on_user_id_and_archived"
    t.index ["user_id"], name: "index_financial_accounts_on_user_id"
    t.check_constraint "account_type IN ('cash', 'bank', 'savings', 'e_wallet', 'credit_card', 'other')", name: "financial_accounts_type_check"
    t.check_constraint "length(currency) = 3", name: "financial_accounts_currency_check"
  end

  create_table "monthly_closes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.bigint "expense_minor", null: false
    t.bigint "income_minor", null: false
    t.integer "month", null: false
    t.bigint "net_minor", null: false
    t.json "totals_by_currency", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "year", null: false
    t.index ["user_id", "year", "month"], name: "index_monthly_closes_on_user_id_and_year_and_month", unique: true
    t.index ["user_id"], name: "index_monthly_closes_on_user_id"
    t.check_constraint "income_minor >= 0 AND expense_minor >= 0", name: "monthly_closes_nonnegative_totals_check"
    t.check_constraint "json_type(totals_by_currency) = 'object'", name: "monthly_closes_currency_totals_object_check"
    t.check_constraint "length(currency) = 3", name: "monthly_closes_currency_length_check"
    t.check_constraint "month >= 1 AND month <= 12", name: "monthly_closes_month_check"
    t.check_constraint "net_minor = (income_minor - expense_minor)", name: "monthly_closes_net_check"
    t.check_constraint "year >= 2000 AND year <= 2200", name: "monthly_closes_year_check"
  end

  create_table "recurring_transactions", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "amount_minor", null: false
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.string "description", limit: 240
    t.bigint "financial_account_id", null: false
    t.string "frequency", null: false
    t.string "kind", null: false
    t.date "next_on", null: false
    t.bigint "transfer_account_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_recurring_transactions_on_category_id"
    t.index ["financial_account_id"], name: "index_recurring_transactions_on_financial_account_id"
    t.index ["transfer_account_id"], name: "index_recurring_transactions_on_transfer_account_id"
    t.index ["user_id"], name: "index_recurring_transactions_on_user_id"
    t.check_constraint "amount_minor > 0", name: "recurring_transactions_positive_amount_check"
    t.check_constraint "frequency IN ('weekly', 'monthly', 'yearly')", name: "recurring_transactions_frequency_check"
    t.check_constraint "kind = 'transfer' AND transfer_account_id IS NOT NULL AND category_id IS NULL OR (kind IN ('income', 'expense')) AND transfer_account_id IS NULL AND category_id IS NOT NULL", name: "recurring_transactions_shape_check"
    t.check_constraint "kind IN ('income', 'expense', 'transfer')", name: "recurring_transactions_kind_check"
    t.check_constraint "length(currency) = 3", name: "recurring_transactions_currency_length_check"
    t.check_constraint "transfer_account_id IS NULL OR transfer_account_id <> financial_account_id", name: "recurring_transactions_distinct_accounts_check"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "amount_minor", null: false
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.string "description", limit: 240
    t.bigint "financial_account_id", null: false
    t.string "idempotency_key", limit: 64
    t.string "kind", null: false
    t.string "receipt_reference", limit: 500
    t.string "source", default: "web", null: false
    t.date "transaction_date", null: false
    t.bigint "transfer_account_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["financial_account_id"], name: "index_transactions_on_financial_account_id"
    t.index ["transfer_account_id"], name: "index_transactions_on_transfer_account_id"
    t.index ["user_id", "category_id", "kind", "currency", "transaction_date"], name: "index_transactions_for_category_reports"
    t.index ["user_id", "idempotency_key"], name: "index_transactions_on_user_and_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["user_id", "kind", "currency", "transaction_date"], name: "index_transactions_for_period_totals"
    t.index ["user_id", "kind", "transaction_date"], name: "index_transactions_on_user_id_and_kind_and_transaction_date"
    t.index ["user_id", "transaction_date", "id"], name: "index_transactions_on_user_id_and_transaction_date_and_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
    t.check_constraint "amount_minor > 0", name: "transactions_positive_amount_check"
    t.check_constraint "kind = 'transfer' AND transfer_account_id IS NOT NULL AND category_id IS NULL OR (kind IN ('income', 'expense')) AND transfer_account_id IS NULL AND category_id IS NOT NULL", name: "transactions_shape_check"
    t.check_constraint "kind IN ('income', 'expense', 'transfer')", name: "transactions_kind_check"
    t.check_constraint "length(currency) = 3", name: "transactions_currency_check"
    t.check_constraint "transfer_account_id IS NULL OR transfer_account_id <> financial_account_id", name: "transactions_distinct_transfer_accounts_check"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "country_code", limit: 2, default: "IN", null: false
    t.datetime "created_at", null: false
    t.string "default_currency", limit: 3, default: "INR", null: false
    t.string "display_name", null: false
    t.string "email_address", null: false
    t.string "locale", limit: 8, default: "en", null: false
    t.string "password_digest", null: false
    t.datetime "suspended_at"
    t.string "timezone", default: "Kolkata", null: false
    t.datetime "updated_at", null: false
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["suspended_at"], name: "index_users_on_suspended_at"
  end

  add_foreign_key "account_reconciliations", "financial_accounts"
  add_foreign_key "account_reconciliations", "users"
  add_foreign_key "audit_events", "users", column: "actor_user_id"
  add_foreign_key "audit_events", "users", column: "subject_user_id"
  add_foreign_key "budget_categories", "budgets"
  add_foreign_key "budget_categories", "categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "financial_accounts", "users"
  add_foreign_key "monthly_closes", "users"
  add_foreign_key "recurring_transactions", "categories"
  add_foreign_key "recurring_transactions", "financial_accounts"
  add_foreign_key "recurring_transactions", "financial_accounts", column: "transfer_account_id"
  add_foreign_key "recurring_transactions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "financial_accounts"
  add_foreign_key "transactions", "financial_accounts", column: "transfer_account_id"
  add_foreign_key "transactions", "users"
end
