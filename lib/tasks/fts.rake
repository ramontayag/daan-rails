# schema.rb cannot represent SQLite triggers, so we recreate them
# after every schema load (e.g. db:test:prepare, db:schema:load).

Rake::Task["db:schema:load"].enhance do
  Daan::Core::FtsTriggers.create(ActiveRecord::Base.connection)
end

Rake::Task["db:test:load_schema"].enhance do
  ActiveRecord::Tasks::DatabaseTasks.with_temporary_pool_for_each(env: "test", name: "primary") do |pool|
    pool.with_connection { |conn| Daan::Core::FtsTriggers.create(conn) }
  end
end
