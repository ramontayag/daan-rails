# test/lib/daan/core/hook_dispatch_test.rb
require "test_helper"

class Daan::Core::HookDispatchTest < ActiveSupport::TestCase
  # A minimal fake tool: just returns its input as a string.
  class FakeTool
    def name; "fake_tool"; end
    def execute(timeout_seconds: nil, **kwargs)
      "result:#{kwargs.inspect}"
    end
  end

  setup do
    @fake_tool = FakeTool.new
    @fake_tool.singleton_class.prepend(Daan::Core::HookDispatch)
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "test_agent", display_name: "T", model_name: "m",
                      system_prompt: "s", max_steps: 1)
    )
    @chat = Chat.create!(agent_name: "test_agent")
  end

  teardown { Thread.current[:daan_active_hooks] = nil }

  test "calls execute normally when no thread-local hooks set" do
    result = @fake_tool.execute(foo: "bar")
    assert_equal "result:#{({ foo: "bar" }).inspect}", result
  end

  test "dispatches before_tool_call to applicable hooks with args" do
    received = nil
    hook = hook_for("fake_tool") { |chat:, tool_name:, args:| received = { chat: chat, tool_name: tool_name, args: args } }
    with_active_hooks([ hook ]) { @fake_tool.execute(foo: "bar") }
    assert_not_nil received
    assert_equal "fake_tool", received[:tool_name]
    assert_equal @chat, received[:chat]
    assert_equal({ foo: "bar" }, received[:args])
  end

  test "dispatches after_tool_call to applicable hooks with result and args" do
    received = nil
    hook = after_hook_for("fake_tool") { |chat:, tool_name:, args:, result:| received = { result: result, args: args } }
    with_active_hooks([ hook ]) { @fake_tool.execute(foo: "bar") }
    assert_equal "result:#{({ foo: "bar" }).inspect}", received[:result]
    assert_equal({ foo: "bar" }, received[:args])
  end

  test "does not dispatch to hooks that don't apply to this tool" do
    called = false
    hook = hook_for("other_tool") { |**| called = true }
    with_active_hooks([ hook ]) { @fake_tool.execute }
    assert_not called
  end

  test "a hook that raises during before_tool_call does not abort execution" do
    boom = hook_for("fake_tool") { |**| raise "before boom" }
    result = nil
    with_active_hooks([ boom ]) { result = @fake_tool.execute(x: 1) }
    assert_equal "result:#{({ x: 1 }).inspect}", result
  end

  test "a hook that raises during after_tool_call does not abort execution" do
    boom = after_hook_for("fake_tool") { |**| raise "after boom" }
    result = nil
    with_active_hooks([ boom ]) { result = @fake_tool.execute(x: 1) }
    assert_equal "result:#{({ x: 1 }).inspect}", result
  end

  private

  # Build a spy hook whose applies_to_tool? returns true for `tool_name`
  # and whose before_tool_call calls the given block.
  def hook_for(tool_name, &blk)
    tn = tool_name
    Class.new do
      def applies_to_tool?(name); name == @tool_name; end
      define_method(:initialize) { @tool_name = tn }
      define_method(:before_tool_call, &blk)
      def after_tool_call(chat:, tool_name:, args:, result:); end
    end.new
  end

  def after_hook_for(tool_name, &blk)
    tn = tool_name
    Class.new do
      def applies_to_tool?(name); name == @tool_name; end
      define_method(:initialize) { @tool_name = tn }
      def before_tool_call(chat:, tool_name:, args:); end
      define_method(:after_tool_call, &blk)
    end.new
  end

  def with_active_hooks(hooks)
    Thread.current[:daan_active_hooks] = { hooks: hooks, chat: @chat }
    yield
  ensure
    Thread.current[:daan_active_hooks] = nil
  end
end
