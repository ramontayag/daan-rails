# test/lib/daan/agent_loader_override_test.rb
require "test_helper"

class AgentLoaderOverrideTest < ActiveSupport::TestCase
  test "config/agents/ override takes precedence over lib/daan/core/agents/" do
    base_dir = Dir.mktmpdir
    override_dir = Dir.mktmpdir

    File.write(File.join(base_dir, "tester.md"), <<~MD)
      ---
      name: tester
      display_name: Tester Base
      model: claude-sonnet-4-20250514
      max_steps: 5
      ---
      Base prompt.
    MD

    File.write(File.join(override_dir, "tester.md"), <<~MD)
      ---
      name: tester
      display_name: Tester Override
      model: claude-sonnet-4-20250514
      max_steps: 5
      ---
      Override prompt.
    MD

    Daan::Core::AgentLoader.sync!(base_dir)
    Daan::Core::AgentLoader.sync!(override_dir)

    agent = Daan::Core::AgentRegistry.find("tester")
    assert_equal "Tester Override", agent.display_name
  ensure
    FileUtils.rm_rf(base_dir)
    FileUtils.rm_rf(override_dir)
  end
end
