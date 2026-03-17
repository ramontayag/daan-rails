require "test_helper"

class ComposeBarComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders form when not readonly" do
    render_inline(ComposeBarComponent.new(action: "/messages"))
    assert_includes rendered_content, "data-testid=\"compose-bar\""
    assert_includes rendered_content, "data-testid=\"message-input\""
    assert_includes rendered_content, "data-testid=\"send-button\""
  end

  test "renders read-only notice when readonly" do
    render_inline(ComposeBarComponent.new(action: "/messages", readonly: true))
    assert_includes rendered_content, "data-testid=\"compose-bar\""
    assert_not_includes rendered_content, "data-testid=\"message-input\""
    assert_includes rendered_content, "read-only"
  end

  test "applies autofocus when autofocus is true" do
    render_inline(ComposeBarComponent.new(action: "/messages", autofocus: true))
    assert_includes rendered_content, "autofocus=\"autofocus\""
  end

  test "does not apply autofocus when autofocus is false" do
    render_inline(ComposeBarComponent.new(action: "/messages", autofocus: false))
    assert_not_includes rendered_content, "autofocus=\"autofocus\""
  end

  test "defaults to no autofocus when autofocus parameter is not provided" do
    render_inline(ComposeBarComponent.new(action: "/messages"))
    assert_not_includes rendered_content, "autofocus=\"autofocus\""
  end
end
