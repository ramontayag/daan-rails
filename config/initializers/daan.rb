Rails.application.config.to_prepare do
  next if Rails.env.test? # Tests load the registry explicitly in setup
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  if Rails.env.development?
    override_dir = Rails.root.join("config/agents")
    Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
  end
end
