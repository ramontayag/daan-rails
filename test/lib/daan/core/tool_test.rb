require "test_helper"

class Daan::Core::ToolTest < ActiveSupport::TestCase
  test "raises if included directly without .module" do
    error = assert_raises(RuntimeError) do
      Class.new(RubyLLM::Tool) { include Daan::Core::Tool }
    end
    assert_match(/Use.*\.module/, error.message)
  end

  test ".module(timeout:) adds tool_timeout_seconds to the including class" do
    klass = Class.new(RubyLLM::Tool) { include Daan::Core::Tool.module(timeout: 42.seconds) }
    assert_equal 42.seconds, klass.tool_timeout_seconds
  end

  test ".module(timeout:) adds tool_name class method returning RubyLLM-derived name" do
    klass = Class.new(RubyLLM::Tool) do
      include Daan::Core::Tool.module(timeout: 5.seconds)
    end
    assert_respond_to klass, :tool_name
    assert_equal klass.new.name, klass.tool_name
  end

  test "Daan::Core::UpdateDocument.tool_name returns the stored tool call name" do
    assert_equal Daan::Core::UpdateDocument.new.name, Daan::Core::UpdateDocument.tool_name
  end
end
