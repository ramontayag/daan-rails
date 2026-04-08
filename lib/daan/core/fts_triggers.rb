module Daan
  module Core
    module FtsTriggers
      STATEMENTS = [
        <<~SQL,
          CREATE TRIGGER IF NOT EXISTS messages_fts_ai AFTER INSERT ON messages
          WHEN new.role IN ('user', 'assistant')
          BEGIN
            INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
          END;
        SQL
        <<~SQL,
          CREATE TRIGGER IF NOT EXISTS messages_fts_ad AFTER DELETE ON messages
          WHEN old.role IN ('user', 'assistant')
          BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
          END;
        SQL
        <<~SQL
          CREATE TRIGGER IF NOT EXISTS messages_fts_au AFTER UPDATE OF content ON messages
          WHEN new.role IN ('user', 'assistant')
          BEGIN
            INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
            INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
          END;
        SQL
      ].freeze

      def self.create(connection)
        STATEMENTS.each { |sql| connection.execute(sql) }
      end
    end
  end
end
