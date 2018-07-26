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

ActiveRecord::Schema.define(version: 20180726125209) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "properties", force: :cascade do |t|
    t.string "label"
    t.string "language"
    t.string "value_datatype"
    t.string "uri"
    t.bigint "rdfs_class_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rdfs_class_id"], name: "index_properties_on_rdfs_class_id"
  end

  create_table "rdfs_classes", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sources", force: :cascade do |t|
    t.string "algorithm_value"
    t.boolean "selected"
    t.string "selected_by"
    t.bigint "next_step"
    t.boolean "render_js"
    t.bigint "property_id"
    t.bigint "website_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_sources_on_property_id"
    t.index ["website_id"], name: "index_sources_on_website_id"
  end

  create_table "statements", force: :cascade do |t|
    t.string "cache"
    t.string "status"
    t.string "status_origin"
    t.datetime "cache_refreshed"
    t.datetime "cache_changed"
    t.bigint "property_id"
    t.bigint "webpage_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["property_id"], name: "index_statements_on_property_id", unique: true
    t.index ["webpage_id"], name: "index_statements_on_webpage_id", unique: true
  end

  create_table "webpages", force: :cascade do |t|
    t.string "url"
    t.string "language"
    t.string "rdf_uri"
    t.bigint "rdfs_class_id"
    t.bigint "website_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rdfs_class_id"], name: "index_webpages_on_rdfs_class_id"
    t.index ["website_id"], name: "index_webpages_on_website_id"
  end

  create_table "websites", force: :cascade do |t|
    t.string "name"
    t.string "seedurl"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "properties", "rdfs_classes"
  add_foreign_key "sources", "properties"
  add_foreign_key "sources", "websites"
  add_foreign_key "statements", "properties"
  add_foreign_key "statements", "webpages"
  add_foreign_key "webpages", "rdfs_classes"
  add_foreign_key "webpages", "websites"
end
