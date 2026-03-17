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

  test "wires form-reset controller" do
    render_inline(ComposeBarComponent.new(action: "/messages"))
    assert_includes rendered_content, "form-reset"
    assert_includes rendered_content, "turbo:submit-end-&gt;form-reset#reset"
  end
end
