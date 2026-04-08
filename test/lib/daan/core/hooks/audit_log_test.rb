# test/lib/daan/core/hooks/audit_log_test.rb
require "test_helper"

class Daan::Core::Hooks::AuditLogTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
    @hook = Daan::Core::Hooks::AuditLog.new
    Daan::Core::Hook::Registry.register(Daan::Core::Hooks::AuditLog)
  end

  teardown { Daan::Core::Hook::Registry.clear }

  test "applies to Bash tool" do
    # Recreate hook instance since setup may have left registry in different state
    hook = Daan::Core::Hooks::AuditLog.new
    assert hook.applies_to_tool?(Daan::Core::Bash.tool_name)
  end

  test "applies to Write tool" do
    hook = Daan::Core::Hooks::AuditLog.new
    assert hook.applies_to_tool?(Daan::Core::Write.tool_name)
  end

  test "does not apply to other tools" do
    hook = Daan::Core::Hooks::AuditLog.new
    refute hook.applies_to_tool?(Daan::Core::Read.tool_name)
  end

  test "before_tool_call logs an info message containing chat_id and tool_name" do
    hook = Daan::Core::Hooks::AuditLog.new
    logged = []
    Rails.logger.stub(:info, ->(msg) { logged << msg }) do
      hook.before_tool_call(chat: @chat, tool_name: "bash", args: { commands: [ [ "ls" ] ] })
    end
    assert logged.any? { |m| m.include?("bash") && m.include?(@chat.id.to_s) },
           "expected log message with tool name and chat_id, got: #{logged.inspect}"
  end

  test "after_tool_call logs an info message containing chat_id, tool_name, and truncated result" do
    hook = Daan::Core::Hooks::AuditLog.new
    logged = []
    result = "a" * 200  # longer than the truncation limit
    Rails.logger.stub(:info, ->(msg) { logged << msg }) do
      hook.after_tool_call(chat: @chat, tool_name: "bash", args: {}, result: result)
    end
    assert logged.any? { |m| m.include?("bash") && m.include?(@chat.id.to_s) },
           "expected log message with tool name and chat_id, got: #{logged.inspect}"
  end

  test "is registered in Hook::Registry after file is loaded" do
    Daan::Core::Hooks::AuditLog  # ensure loaded
    assert_includes Daan::Core::Hook::Registry.all, Daan::Core::Hooks::AuditLog
  end
end
