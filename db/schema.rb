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

ActiveRecord::Schema[8.1].define(version: 2026_07_08_022643) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "tours", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "entrypoint", null: false
    t.string "git_ref"
    t.string "repo_path", null: false
    t.string "status", default: "idle", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "trace_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "entrypoint"
    t.integer "event_count", default: 0, null: false
    t.jsonb "events", default: [], null: false
    t.string "git_ref"
    t.string "label", null: false
    t.bigint "tour_id"
    t.datetime "updated_at", null: false
    t.index ["tour_id"], name: "index_trace_runs_on_tour_id"
  end

  create_table "waypoints", force: :cascade do |t|
    t.string "author"
    t.string "change_kind"
    t.string "condition"
    t.datetime "created_at", null: false
    t.string "file", null: false
    t.integer "line", null: false
    t.text "note"
    t.integer "position", default: 0, null: false
    t.bigint "tour_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tour_id", "position"], name: "index_waypoints_on_tour_id_and_position"
    t.index ["tour_id"], name: "index_waypoints_on_tour_id"
  end

  add_foreign_key "trace_runs", "tours"
  add_foreign_key "waypoints", "tours"
end
