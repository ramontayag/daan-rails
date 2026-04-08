Rails.application.config.to_prepare do
  next if Rails.env.test? # Tests load the registry and configure allowed_commands explicitly

  Daan::Core.configure do |c|
    c.allowed_commands = %w[
      cd git gh ls grep find head tail wc diff pwd cat sort
      bundle bin/rubocop bin/rails bin/rake bin/ci ruby gem
      rm mkdir cp mv echo sed cut xargs
    ]
  end

  # Force-load hooks so they self-register via Hook::Registry at boot.
  # In production Zeitwerk eager-loads everything, but in development it doesn't.
  # Once daan-core is a gem this moves into its Railtie.
  Rails.autoloaders.main.eager_load_dir(Rails.root.join("lib/daan/core/hooks"))
  Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  if Rails.env.development?
    override_dir = Rails.root.join("config/agents")
    Daan::Core::AgentLoader.sync!(override_dir) if override_dir.exist?
  end
end
