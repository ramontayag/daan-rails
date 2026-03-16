require "test_helper"

class Daan::Core::SafeExecuteTest < ActiveSupport::TestCase
  setup do
    @tool_class = Class.new(RubyLLM::Tool) do
      extend Daan::Core::ToolTimeout
      tool_timeout_seconds 10.seconds

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
      tool_timeout_seconds 0.1.seconds

      def execute
        sleep 1
        "should not reach here"
      end
    end
    tool = slow_class.new
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    result = tool.execute
    assert_match(/Error: timed out after/, result)
  end

  test "uses DEFAULT_TIMEOUT_SECONDS when tool_timeout_seconds returns nil" do
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

  test "allows LLM to override timeout via timeout_seconds param" do
    slow_class = Class.new(RubyLLM::Tool) do
      extend Daan::Core::ToolTimeout
      tool_timeout_seconds 0.1.seconds

      def execute
        sleep 0.3
        "done"
      end
    end
    tool = slow_class.new
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    # Default timeout (0.1s) should cause a timeout
    result = tool.execute
    assert_match(/timed out/, result)

    # LLM overrides with longer timeout — should succeed
    result = tool.execute(timeout_seconds: 2)
    assert_equal "done", result
  end

  test "returns error when timeout_seconds exceeds maximum" do
    tool = @tool_class.new
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    max = Daan::Core::SafeExecute::MAX_TIMEOUT_SECONDS.to_i
    result = tool.execute(timeout_seconds: max + 1)
    assert_match(/exceeds maximum of #{max}/, result)
  end

  test "injects timeout_seconds into params_schema" do
    schema = @tool.params_schema
    assert schema["properties"].key?("timeout_seconds")
    assert_match(/max: #{Daan::Core::SafeExecute::MAX_TIMEOUT_SECONDS.to_i}/, schema["properties"]["timeout_seconds"]["description"])
  end
end
