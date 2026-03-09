# test/components/typing_indicator_component_test.rb
require "test_helper"

class TypingIndicatorComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders typing text when typing is true" do
    render_inline(TypingIndicatorComponent.new(typing: true))
    assert_includes rendered_content, "Typing"
  end

  test "renders nothing visible when typing is false" do
    render_inline(TypingIndicatorComponent.new(typing: false))
    refute_includes rendered_content, "Typing"
  end
end
