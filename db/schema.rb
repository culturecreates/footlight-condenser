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

ActiveRecord::Schema[8.0].define(version: 2024_10_28_141852) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

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
  end

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
