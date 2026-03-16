require "test_helper"

class Daan::Core::ToolTimeoutTest < ActiveSupport::TestCase
  test "all tools declare an explicit tool_timeout_seconds" do
    tool_classes = Daan::Core.constants
      .map { |c| Daan::Core.const_get(c) }
      .select { |c| c.is_a?(Class) && c < RubyLLM::Tool }

    assert tool_classes.any?, "Expected to find tool classes under Daan::Core"

    tool_classes.each do |klass|
      assert klass.respond_to?(:tool_timeout_seconds),
        "#{klass} must `extend Daan::Core::ToolTimeout` and declare a tool_timeout_seconds"
      assert_not_nil klass.tool_timeout_seconds,
        "#{klass} must declare an explicit tool_timeout_seconds value"
    end
  end
end
