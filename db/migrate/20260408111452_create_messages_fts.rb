class CreateMessagesFts < ActiveRecord::Migration[8.1]
  def up
    create_virtual_table :messages_fts, :fts5, [
      "content",
      "content='messages'",
      "content_rowid='id'"
    ]

    execute <<~SQL
      CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages
      WHEN new.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages
      WHEN old.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
      END;
    SQL

    execute <<~SQL
      CREATE TRIGGER messages_fts_au AFTER UPDATE OF content ON messages
      WHEN new.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
        INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
      END;
    SQL

    execute <<~SQL
      INSERT INTO messages_fts(rowid, content)
      SELECT id, content FROM messages WHERE role IN ('user', 'assistant');
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS messages_fts_au"
    execute "DROP TRIGGER IF EXISTS messages_fts_ad"
    execute "DROP TRIGGER IF EXISTS messages_fts_ai"
    drop_virtual_table :messages_fts, :fts5, [
      "content",
      "content='messages'",
      "content_rowid='id'"
    ]
  end
end
