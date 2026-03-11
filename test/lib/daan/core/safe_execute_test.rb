require "test_helper"

class Daan::Core::SafeExecuteTest < ActiveSupport::TestCase
  setup do
    @tool = Class.new(RubyLLM::Tool) do
      def execute(raise_error: false)
        raise "boom" if raise_error
        "ok"
      end
    end.new
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
  end

  test "passes through successful execute result" do
    assert_equal "ok", @tool.execute(raise_error: false)
  end

  test "returns error string instead of raising" do
    result = @tool.execute(raise_error: true)
    assert_match(/Error.*boom/, result)
  end
end
