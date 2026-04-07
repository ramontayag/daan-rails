require "test_helper"

class AgentActivityIndicatorComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders typing message when status is :typing" do
    render_inline(AgentActivityIndicatorComponent.new(status: :typing))
    assert_includes rendered_content, "Typing..."
  end

  test "renders queued message when status is :queued" do
    render_inline(AgentActivityIndicatorComponent.new(status: :queued))
    assert_includes rendered_content, "Working on something else..."
  end

  test "renders nothing when status is nil" do
    render_inline(AgentActivityIndicatorComponent.new(status: nil))
    refute_includes rendered_content, "Typing"
    refute_includes rendered_content, "Working"
  end
end
