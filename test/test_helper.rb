ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "minitest/mock"
require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.default_cassette_options = { record: :new_episodes }
  config.ignore_localhost = true
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup    { Daan::AgentRegistry.clear; Daan::Core::Hook::Registry.clear; Daan::Core.configuration.reset }
    teardown { Daan::AgentRegistry.clear; Daan::Core::Hook::Registry.clear; Daan::Core.configuration.reset }

    private

    def fake_anthropic_response(text: "ok")
      {
        id: "msg_fake",
        type: "message",
        role: "assistant",
        model: "claude-haiku-4-5-20251001",
        content: [ { type: "text", text: text } ],
        stop_reason: "end_turn",
        stop_sequence: nil,
        usage: { input_tokens: 10, output_tokens: 5 }
      }.to_json
    end
  end
end
