CREATE TABLE "models" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "capabilities" json DEFAULT '[]', "context_window" integer, "created_at" datetime(6) NOT NULL, "family" varchar, "knowledge_cutoff" date, "max_output_tokens" integer, "metadata" json DEFAULT '{}', "modalities" json DEFAULT '{}', "model_created_at" datetime(6), "model_id" varchar NOT NULL, "name" varchar NOT NULL, "pricing" json DEFAULT '{}', "provider" varchar NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE INDEX "index_models_on_family" ON "models" ("family") /*application='Daan'*/;
CREATE UNIQUE INDEX "index_models_on_provider_and_model_id" ON "models" ("provider", "model_id") /*application='Daan'*/;
CREATE INDEX "index_models_on_provider" ON "models" ("provider") /*application='Daan'*/;
CREATE TABLE "chat_steps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "chat_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "position" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "title" varchar NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_657683fe4c"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
);
CREATE UNIQUE INDEX "index_chat_steps_on_chat_id_and_position" ON "chat_steps" ("chat_id", "position") /*application='Daan'*/;
CREATE INDEX "index_chat_steps_on_chat_id" ON "chat_steps" ("chat_id") /*application='Daan'*/;
CREATE TABLE "chats" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_name" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "model_id" integer, "parent_chat_id" integer, "task_status" varchar DEFAULT 'pending' NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_0c85fe670b"
FOREIGN KEY ("parent_chat_id")
  REFERENCES "chats" ("id")
, CONSTRAINT "fk_rails_1835d93df1"
FOREIGN KEY ("model_id")
  REFERENCES "models" ("id")
);
CREATE INDEX "index_chats_on_agent_name" ON "chats" ("agent_name") /*application='Daan'*/;
CREATE INDEX "index_chats_on_model_id" ON "chats" ("model_id") /*application='Daan'*/;
CREATE INDEX "index_chats_on_parent_chat_id" ON "chats" ("parent_chat_id") /*application='Daan'*/;
CREATE TABLE "documents" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "body" text, "chat_id" integer NOT NULL, "created_at" datetime(6) NOT NULL, "title" varchar NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_adcff66c9e"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
);
CREATE INDEX "index_documents_on_chat_id" ON "documents" ("chat_id") /*application='Daan'*/;
CREATE TABLE "messages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "cache_creation_tokens" integer, "cached_tokens" integer, "chat_id" integer NOT NULL, "compacted_message_id" integer, "compacted_messages_count" integer DEFAULT 0 NOT NULL, "content" text, "content_raw" json, "context_user_message_id" integer, "created_at" datetime(6) NOT NULL, "input_tokens" integer, "model_id" integer, "output_tokens" integer, "role" varchar NOT NULL, "thinking_signature" text, "thinking_text" text, "thinking_tokens" integer, "tool_call_id" integer, "updated_at" datetime(6) NOT NULL, "visible" boolean DEFAULT TRUE NOT NULL, CONSTRAINT "fk_rails_c02b47ad97"
FOREIGN KEY ("model_id")
  REFERENCES "models" ("id")
, CONSTRAINT "fk_rails_0f670de7ba"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
, CONSTRAINT "fk_rails_32538332a2"
FOREIGN KEY ("compacted_message_id")
  REFERENCES "messages" ("id")
, CONSTRAINT "fk_rails_552873cb52"
FOREIGN KEY ("tool_call_id")
  REFERENCES "tool_calls" ("id")
);
CREATE INDEX "index_messages_on_chat_id" ON "messages" ("chat_id") /*application='Daan'*/;
CREATE INDEX "index_messages_on_compacted_message_id" ON "messages" ("compacted_message_id") /*application='Daan'*/;
CREATE INDEX "index_messages_on_model_id" ON "messages" ("model_id") /*application='Daan'*/;
CREATE INDEX "index_messages_on_role" ON "messages" ("role") /*application='Daan'*/;
CREATE INDEX "index_messages_on_tool_call_id" ON "messages" ("tool_call_id") /*application='Daan'*/;
CREATE TABLE "scheduled_tasks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_name" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "enabled" boolean DEFAULT TRUE NOT NULL, "last_enqueued_at" datetime(6), "message" text NOT NULL, "run_at" datetime(6), "schedule" varchar, "source_chat_id" bigint, "task_type" integer DEFAULT 0 NOT NULL, "timezone" varchar DEFAULT 'UTC', "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7e0f253ca6"
FOREIGN KEY ("source_chat_id")
  REFERENCES "chats" ("id")
);
CREATE INDEX "index_scheduled_tasks_on_agent_name" ON "scheduled_tasks" ("agent_name") /*application='Daan'*/;
CREATE INDEX "index_scheduled_tasks_on_enabled" ON "scheduled_tasks" ("enabled") /*application='Daan'*/;
CREATE INDEX "index_scheduled_tasks_on_source_chat_id" ON "scheduled_tasks" ("source_chat_id") /*application='Daan'*/;
CREATE INDEX "index_scheduled_tasks_on_type_enabled_run_at" ON "scheduled_tasks" ("task_type", "enabled", "run_at") /*application='Daan'*/;
CREATE TABLE "tool_calls" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "arguments" json DEFAULT '{}', "created_at" datetime(6) NOT NULL, "message_id" integer NOT NULL, "name" varchar NOT NULL, "thought_signature" varchar, "tool_call_id" varchar NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_9c8daee481"
FOREIGN KEY ("message_id")
  REFERENCES "messages" ("id")
);
CREATE INDEX "index_tool_calls_on_message_id" ON "tool_calls" ("message_id") /*application='Daan'*/;
CREATE INDEX "index_tool_calls_on_name" ON "tool_calls" ("name") /*application='Daan'*/;
CREATE UNIQUE INDEX "index_tool_calls_on_tool_call_id" ON "tool_calls" ("tool_call_id") /*application='Daan'*/;
CREATE TABLE "workspace_locks" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_name" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "holder_chat_id" integer, "previous_holder_chat_id" integer, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_f368d58a26"
FOREIGN KEY ("holder_chat_id")
  REFERENCES "chats" ("id")
, CONSTRAINT "fk_rails_f16751db1c"
FOREIGN KEY ("previous_holder_chat_id")
  REFERENCES "chats" ("id")
);
CREATE UNIQUE INDEX "index_workspace_locks_on_agent_name" ON "workspace_locks" ("agent_name") /*application='Daan'*/;
CREATE INDEX "index_workspace_locks_on_holder_chat_id" ON "workspace_locks" ("holder_chat_id") /*application='Daan'*/;
CREATE INDEX "index_workspace_locks_on_previous_holder_chat_id" ON "workspace_locks" ("previous_holder_chat_id") /*application='Daan'*/;
CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE VIRTUAL TABLE messages_fts USING fts5(
  content,
  content='messages',
  content_rowid='id'
)
/* messages_fts(content) */;
CREATE TABLE 'messages_fts_data'(id INTEGER PRIMARY KEY, block BLOB);
CREATE TABLE 'messages_fts_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID;
CREATE TABLE 'messages_fts_docsize'(id INTEGER PRIMARY KEY, sz BLOB);
CREATE TABLE 'messages_fts_config'(k PRIMARY KEY, v) WITHOUT ROWID;
CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages
WHEN new.role IN ('user', 'assistant')
BEGIN
  INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;
CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages
WHEN old.role IN ('user', 'assistant')
BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
END;
CREATE TRIGGER messages_fts_au AFTER UPDATE OF content ON messages
WHEN new.role IN ('user', 'assistant')
BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
  INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;
INSERT INTO "schema_migrations" (version) VALUES
('20260408111452'),
('20260407095453'),
('20260407094501'),
('20260327173639'),
('20260327173355'),
('20260327164609'),
('20260325113722'),
('20260324174437'),
('20260319162813'),
('20260317201603'),
('20260312222151'),
('20260310152318'),
('20260309215556'),
('20260306154916'),
('20260306152415'),
('20260306152414'),
('20260306152412'),
('20260306152411'),
('20260306152410');

