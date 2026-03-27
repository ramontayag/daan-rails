Rails.application.config.to_prepare do
  next if Rails.env.test? # Tests load the registry explicitly in setup
  # Force-load hooks so they self-register via Hook::Registry at boot.
  # In production Zeitwerk eager-loads everything, but in development it doesn't.
  # Once daan-core is a gem this moves into its Railtie.
  Rails.autoloaders.main.eager_load_dir(Rails.root.join("lib/daan/core/hooks"))
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  if Rails.env.development?
    override_dir = Rails.root.join("config/agents")
    Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
  end
end
