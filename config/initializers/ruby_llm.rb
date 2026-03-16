RubyLLM.configure do |config|
<<<<<<< HEAD
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "test-key-placeholder")
  config.openai_api_key    = ENV.fetch("OPENAI_API_KEY", "test-key-placeholder")
=======
  # In test environment, allow missing API key or use a dummy key
  if Rails.env.test?
    config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", "sk-test-dummy-key")
  else
    config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY")
  end
  
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
>>>>>>> feature/sidebar-highlighting-bug-fix

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end