require "test_helper"
require "tmpdir"

class Daan::Core::Hooks::BranchFreshnessTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    workspace = Daan::Workspace.new(@tmpdir)
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "test_agent", display_name: "T", model_name: "m",
                      system_prompt: "s", max_steps: 1, workspace: workspace)
    )
    @chat = Chat.create!(agent_name: "test_agent")
    @hook = Daan::Core::Hooks::BranchFreshness.new
    Daan::Core::Hook::Registry.register(Daan::Core::Hooks::BranchFreshness)
  end

  teardown do
    FileUtils.remove_entry(@tmpdir)
    Daan::Core::Hook::Registry.clear
  end

  test "applies to Bash tool" do
    assert @hook.applies_to_tool?(Daan::Core::Bash.tool_name)
  end

  test "does not apply to other tools" do
    refute @hook.applies_to_tool?(Daan::Core::Read.tool_name)
  end

  test "does not inject message when commands do not include git checkout -b" do
    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "status" ] ] },
      result: ""
    )
    assert_equal 0, @chat.messages.count
  end

  test "does not inject message when branch is based on latest" do
    @hook.define_singleton_method(:fetch_origin) { |*| true }
    @hook.define_singleton_method(:default_branch) { |*| "main" }
    @hook.define_singleton_method(:based_on_latest?) { |*| true }

    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "checkout", "-b", "feat/x" ] ] },
      result: ""
    )
    assert_equal 0, @chat.messages.count
  end

  test "injects message when branch is not based on latest" do
    @hook.define_singleton_method(:fetch_origin) { |*| nil }
    @hook.define_singleton_method(:default_branch) { |*| "main" }
    @hook.define_singleton_method(:based_on_latest?) { |*| false }

    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "checkout", "-b", "feat/x" ] ] },
      result: ""
    )

    assert_equal 1, @chat.messages.count
    msg = @chat.messages.last
    assert_equal "user", msg.role
    assert_includes msg.content, "[SYSTEM]"
    assert_includes msg.content, "origin/main"
    assert_equal false, msg.visible
  end

  test "uses dynamic default branch name in message" do
    @hook.define_singleton_method(:fetch_origin) { |*| nil }
    @hook.define_singleton_method(:default_branch) { |*| "master" }
    @hook.define_singleton_method(:based_on_latest?) { |*| false }

    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "checkout", "-b", "feat/x" ] ] },
      result: ""
    )

    assert_equal 1, @chat.messages.count
    assert_includes @chat.messages.last.content, "origin/master"
  end

  test "injects message when fetch fails (fail open)" do
    @hook.define_singleton_method(:fetch_origin) { |*| false }
    @hook.define_singleton_method(:default_branch) { |*| "main" }
    messages_before = @chat.messages.count
    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "checkout", "-b", "feat/something" ] ] },
      result: "Switched to a new branch"
    )
    assert_equal messages_before + 1, @chat.messages.count
    assert_includes @chat.messages.last.content, "[SYSTEM]"
  end

  test "does not inject message when agent has no workspace" do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "test_agent", display_name: "T", model_name: "m",
                      system_prompt: "s", max_steps: 1, workspace: nil)
    )

    @hook.after_tool_call(
      chat: @chat,
      tool_name: "bash",
      args: { commands: [ [ "git", "checkout", "-b", "feat/x" ] ] },
      result: ""
    )

    assert_equal 0, @chat.messages.count
  end
end
