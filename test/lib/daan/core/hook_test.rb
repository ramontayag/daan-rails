require "test_helper"

class Daan::Core::HookTest < ActiveSupport::TestCase
  teardown { Daan::Core::Hook::Registry.clear }

  test "included class is registered in Registry" do
    klass = Class.new { include Daan::Core::Hook }
    assert_includes Daan::Core::Hook::Registry.all, klass
  end

  test "included class gets default no-op before_llm_call" do
    klass = Class.new { include Daan::Core::Hook }
    assert_nothing_raised { klass.new.before_llm_call(chat: nil, last_tool_calls: []) }
  end

  test "applies_to_tool? returns false for plain agent hook includes" do
    klass = Class.new { include Daan::Core::Hook }
    assert_equal false, klass.new.applies_to_tool?("anything")
  end

  test ".module(applies_to:) sets applies_to_tool? for listed tool classes" do
    klass = Class.new { include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash]) }
    assert_equal true,  klass.new.applies_to_tool?(Daan::Core::Bash.tool_name)
    assert_equal false, klass.new.applies_to_tool?(Daan::Core::Write.tool_name)
  end

  test "Registry.agent_hooks resolves constant name strings to instances" do
    stub_hook = Class.new { include Daan::Core::Hook }
    Object.const_set("StubHook", stub_hook)
    instances = Daan::Core::Hook::Registry.agent_hooks(["StubHook"])
    assert_equal 1, instances.size
    assert_instance_of stub_hook, instances.first
  ensure
    Object.send(:remove_const, :StubHook) if Object.const_defined?(:StubHook)
  end

  test "Registry.tool_hooks returns only hooks included via .module(applies_to:)" do
    Class.new { include Daan::Core::Hook }  # agent hook — not a tool hook
    assert_equal [], Daan::Core::Hook::Registry.tool_hooks
  end

  test "Registry.clear removes all registered classes" do
    Class.new { include Daan::Core::Hook }
    Daan::Core::Hook::Registry.clear
    assert_empty Daan::Core::Hook::Registry.all
  end
end
