# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20180725165657) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "object_classes", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "predicates", force: :cascade do |t|
    t.string "label"
    t.string "language"
    t.string "object_datatype"
    t.string "uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sources", force: :cascade do |t|
    t.string "algorithm_value"
    t.boolean "selected"
    t.string "selected_by"
    t.bigint "source_id"
    t.bigint "website_id"
    t.bigint "predicate_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["predicate_id"], name: "index_sources_on_predicate_id"
    t.index ["source_id"], name: "index_sources_on_source_id"
    t.index ["website_id"], name: "index_sources_on_website_id"
  end

  create_table "statements", force: :cascade do |t|
    t.bigint "status_id"
    t.bigint "predicate_id"
    t.bigint "webpage_id"
    t.string "cache"
    t.string "status_origin"
    t.datetime "cache_refreshed"
    t.datetime "cache_changed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["predicate_id"], name: "index_statements_on_predicate_id"
    t.index ["status_id"], name: "index_statements_on_status_id"
    t.index ["webpage_id"], name: "index_statements_on_webpage_id"
  end

  create_table "statuses", force: :cascade do |t|
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "webpages", force: :cascade do |t|
    t.string "url"
    t.string "language"
    t.string "object_uri"
    t.bigint "website_id"
    t.bigint "object_class_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["object_class_id"], name: "index_webpages_on_object_class_id"
    t.index ["website_id"], name: "index_webpages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.string "name"
    t.string "seedurl"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "sources", "predicates"
  add_foreign_key "sources", "sources"
  add_foreign_key "sources", "websites"
  add_foreign_key "statements", "predicates"
  add_foreign_key "statements", "statuses"
  add_foreign_key "statements", "webpages"
  add_foreign_key "webpages", "object_classes"
  add_foreign_key "webpages", "websites"
end
