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

ActiveRecord::Schema[8.0].define(version: 2026_05_19_012000) do
  create_schema "heroku_ext"

  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

  create_table "distillator_fetch_caches", force: :cascade do |t|
    t.string "uri_key", null: false
    t.string "normalized_url"
    t.text "html"
    t.text "body"
    t.string "name"
    t.jsonb "json_ld"
    t.datetime "scrape_date"
    t.datetime "successful_refresh"
    t.integer "http_response_code"
    t.jsonb "headers", default: {}, null: false
    t.jsonb "signals", default: {}, null: false
    t.jsonb "hints", default: [], null: false
    t.string "final_url"
    t.jsonb "redirect_chain", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "health_status"
    t.string "health_severity"
    t.jsonb "health_reasons", default: [], null: false
    t.integer "html_bytes", default: 0, null: false
    t.integer "body_bytes", default: 0, null: false
    t.boolean "redirected", default: false, null: false
    t.string "network_status"
    t.string "content_type"
    t.jsonb "hint_keys", default: [], null: false
    t.string "primary_issue_key"
    t.string "primary_issue_error_code"
    t.string "primary_issue_label"
    t.string "primary_issue_severity"
    t.string "primary_issue_category"
    t.jsonb "issue_keys", default: [], null: false
    t.jsonb "issue_hints", default: [], null: false
    t.boolean "delete_candidate", default: false, null: false
    t.index ["content_type"], name: "index_distillator_fetch_caches_on_content_type"
    t.index ["delete_candidate"], name: "index_distillator_fetch_caches_on_delete_candidate"
    t.index ["health_severity"], name: "index_distillator_fetch_caches_on_health_severity"
    t.index ["health_status"], name: "index_distillator_fetch_caches_on_health_status"
    t.index ["hints"], name: "index_distillator_fetch_caches_on_hints", using: :gin
    t.index ["http_response_code"], name: "index_distillator_fetch_caches_on_http_response_code"
    t.index ["issue_hints"], name: "index_distillator_fetch_caches_on_issue_hints", using: :gin
    t.index ["issue_keys"], name: "index_distillator_fetch_caches_on_issue_keys", using: :gin
    t.index ["network_status"], name: "index_distillator_fetch_caches_on_network_status"
    t.index ["normalized_url"], name: "index_distillator_fetch_caches_on_normalized_url"
    t.index ["primary_issue_category"], name: "index_distillator_fetch_caches_on_primary_issue_category"
    t.index ["primary_issue_key"], name: "index_distillator_fetch_caches_on_primary_issue_key"
    t.index ["primary_issue_severity"], name: "index_distillator_fetch_caches_on_primary_issue_severity"
    t.index ["redirect_chain"], name: "index_distillator_fetch_caches_on_redirect_chain", using: :gin
    t.index ["redirected"], name: "index_distillator_fetch_caches_on_redirected"
    t.index ["scrape_date"], name: "index_distillator_fetch_caches_on_scrape_date"
    t.index ["signals"], name: "index_distillator_fetch_caches_on_signals", using: :gin
    t.index ["successful_refresh"], name: "index_distillator_fetch_caches_on_successful_refresh"
    t.index ["updated_at"], name: "index_distillator_fetch_caches_on_updated_at"
    t.index ["uri_key"], name: "index_distillator_fetch_caches_on_uri_key", unique: true
  end

  create_table "distillator_rollout_events", force: :cascade do |t|
    t.bigint "website_id", null: false
    t.string "from_mode"
    t.string "to_mode", null: false
    t.string "actor"
    t.string "reason"
    t.jsonb "readiness_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["to_mode"], name: "index_distillator_rollout_events_on_to_mode"
    t.index ["website_id", "created_at"], name: "index_distillator_rollout_events_on_website_id_and_created_at"
    t.index ["website_id"], name: "index_distillator_rollout_events_on_website_id"
  end

  create_table "distillator_transition_evidence", force: :cascade do |t|
    t.bigint "website_id", null: false
    t.string "url", null: false
    t.string "cohort_key"
    t.string "check_kind", null: false
    t.string "status", null: false
    t.integer "statement_delta"
    t.boolean "statement_count_delta_acceptable"
    t.boolean "export_diff_checked"
    t.string "export_diff_status"
    t.boolean "export_diff_accepted"
    t.integer "rdf_added_count"
    t.integer "rdf_removed_count"
    t.string "wringer_uri_key"
    t.string "distillator_uri_key"
    t.integer "wringer_http_code"
    t.integer "distillator_http_code"
    t.string "primary_issue_key"
    t.jsonb "details", default: {}, null: false
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["check_kind"], name: "index_distillator_transition_evidence_on_check_kind"
    t.index ["checked_at"], name: "index_distillator_transition_evidence_on_checked_at"
    t.index ["cohort_key"], name: "index_distillator_transition_evidence_on_cohort_key"
    t.index ["status"], name: "index_distillator_transition_evidence_on_status"
    t.index ["website_id", "check_kind", "checked_at"], name: "index_transition_evidence_on_site_kind_checked_at"
    t.index ["website_id", "url", "check_kind", "checked_at"], name: "index_transition_evidence_on_site_url_kind_checked_at"
    t.index ["website_id"], name: "index_distillator_transition_evidence_on_website_id"
  end

  create_table "jsonld_outputs", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.json "frame"
  end

  create_table "messages", force: :cascade do |t|
    t.string "message"
    t.string "artifact"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "properties", force: :cascade do |t|
    t.string "label"
    t.string "value_datatype"
    t.string "uri"
    t.bigint "rdfs_class_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "expected_class"
    t.index ["rdfs_class_id"], name: "index_properties_on_rdfs_class_id"
  end

  create_table "rdfs_classes", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "search_exceptions", force: :cascade do |t|
    t.string "name"
    t.bigint "rdfs_class_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "uri"
    t.index ["rdfs_class_id"], name: "index_search_exceptions_on_rdfs_class_id"
  end

  create_table "sources", force: :cascade do |t|
    t.string "algorithm_value"
    t.boolean "selected"
    t.string "selected_by"
    t.string "language"
    t.boolean "render_js"
    t.bigint "property_id"
    t.bigint "website_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "label"
    t.boolean "auto_review", default: false
    t.index ["property_id"], name: "index_sources_on_property_id"
    t.index ["website_id"], name: "index_sources_on_website_id"
  end

  create_table "statements", force: :cascade do |t|
    t.string "cache"
    t.string "status"
    t.string "status_origin"
    t.datetime "cache_refreshed", precision: nil
    t.datetime "cache_changed", precision: nil
    t.bigint "source_id"
    t.bigint "webpage_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "selected_individual", default: false
    t.boolean "manual", default: false
    t.index ["source_id", "webpage_id"], name: "index_statements_on_source_id_and_webpage_id", unique: true
    t.index ["source_id"], name: "index_statements_on_source_id"
    t.index ["webpage_id"], name: "index_statements_on_webpage_id"
  end

  create_table "webpages", force: :cascade do |t|
    t.string "url"
    t.string "language"
    t.string "rdf_uri"
    t.bigint "rdfs_class_id"
    t.bigint "website_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "archive_date", precision: nil
    t.bigint "jsonld_output_id"
    t.index ["jsonld_output_id"], name: "index_webpages_on_jsonld_output_id"
    t.index ["rdfs_class_id"], name: "index_webpages_on_rdfs_class_id"
    t.index ["url", "website_id"], name: "index_webpages_on_url_and_website_id", unique: true
    t.index ["url"], name: "index_webpages_on_url"
    t.index ["website_id"], name: "index_webpages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.string "name"
    t.string "seedurl"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "graph_name", default: "http://artsdata.ca"
    t.string "default_language", default: "en"
    t.integer "schedule_every_days"
    t.datetime "last_refresh", precision: nil
    t.time "schedule_time"
    t.string "province"
    t.string "city"
    t.boolean "monitorable"
    t.string "distillator_mode", default: "legacy", null: false
    t.index ["distillator_mode"], name: "index_websites_on_distillator_mode"
  end

  add_foreign_key "distillator_rollout_events", "websites"
  add_foreign_key "distillator_transition_evidence", "websites"
  add_foreign_key "properties", "rdfs_classes"
  add_foreign_key "search_exceptions", "rdfs_classes"
  add_foreign_key "sources", "properties"
  add_foreign_key "sources", "websites"
  add_foreign_key "statements", "sources"
  add_foreign_key "statements", "webpages"
  add_foreign_key "webpages", "jsonld_outputs"
  add_foreign_key "webpages", "rdfs_classes"
  add_foreign_key "webpages", "websites"
end
