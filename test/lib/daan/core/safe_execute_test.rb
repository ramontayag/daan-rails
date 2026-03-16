require "test_helper"

class Daan::Core::SafeExecuteTest < ActiveSupport::TestCase
  setup do
    @tool_class = Class.new(RubyLLM::Tool) do
      extend Daan::Core::ToolTimeout
      tool_timeout_seconds 10

      def execute(raise_error: false)
        raise "boom" if raise_error
        "ok"
      end
    end
    @tool = @tool_class.new
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
  end

  test "passes through successful execute result" do
    assert_equal "ok", @tool.execute(raise_error: false)
  end

  test "returns error string instead of raising" do
    result = @tool.execute(raise_error: true)
    assert_match(/Error.*boom/, result)
  end

  test "returns timeout error when tool exceeds its timeout" do
    slow_class = Class.new(RubyLLM::Tool) do
      extend Daan::Core::ToolTimeout
      tool_timeout_seconds 0.1

      def execute
        sleep 1
        "should not reach here"
      end
    end
    tool = slow_class.new
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    result = tool.execute
    assert_match(/Error: timed out after 0.1s/, result)
  end

  test "uses DEFAULT_TIMEOUT when tool_timeout_seconds returns nil" do
    no_timeout_class = Class.new(RubyLLM::Tool) do
      extend Daan::Core::ToolTimeout

      def execute
        "ok"
      end
    end
    tool = no_timeout_class.new
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    assert_equal "ok", tool.execute
  end
end
