RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "test-key-placeholder")
  config.openai_api_key    = ENV.fetch("OPENAI_API_KEY", "test-key-placeholder")

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end