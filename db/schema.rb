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

ActiveRecord::Schema[8.1].define(version: 2026_03_27_173355) do
  create_table "chat_steps", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "position"], name: "index_chat_steps_on_chat_id_and_position", unique: true
    t.index ["chat_id"], name: "index_chat_steps_on_chat_id"
  end

  create_table "chats", force: :cascade do |t|
    t.string "agent_name", null: false
    t.datetime "created_at", null: false
    t.integer "model_id"
    t.integer "parent_chat_id"
    t.string "task_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_name"], name: "index_chats_on_agent_name"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["parent_chat_id"], name: "index_chats_on_parent_chat_id"
  end

  create_table "documents", force: :cascade do |t|
    t.text "body"
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_documents_on_chat_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.integer "chat_id", null: false
    t.integer "compacted_message_id"
    t.integer "compacted_messages_count", default: 0, null: false
    t.text "content"
    t.json "content_raw"
    t.integer "context_user_message_id"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.integer "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.boolean "visible", default: true, null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["compacted_message_id"], name: "index_messages_on_compacted_message_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "scheduled_tasks", force: :cascade do |t|
    t.string "agent_name", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_enqueued_at"
    t.text "message", null: false
    t.datetime "run_at"
    t.string "schedule", null: false
    t.bigint "source_chat_id"
    t.integer "task_type", default: 0, null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_name"], name: "index_scheduled_tasks_on_agent_name"
    t.index ["enabled"], name: "index_scheduled_tasks_on_enabled"
    t.index ["source_chat_id"], name: "index_scheduled_tasks_on_source_chat_id"
    t.index ["task_type", "enabled", "run_at"], name: "index_scheduled_tasks_on_type_enabled_run_at"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.string "name", null: false
    t.string "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  add_foreign_key "chat_steps", "chats"
  add_foreign_key "chats", "chats", column: "parent_chat_id"
  add_foreign_key "chats", "models"
  add_foreign_key "documents", "chats"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "messages", column: "compacted_message_id"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "scheduled_tasks", "chats", column: "source_chat_id"
  add_foreign_key "tool_calls", "messages"
end
