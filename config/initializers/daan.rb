Rails.application.config.after_initialize do
  next if Rails.env.test? # Tests load the registry explicitly in setup
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
end
