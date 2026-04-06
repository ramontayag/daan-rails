require "test_helper"

class PopoverComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders trigger text" do
    render_inline(PopoverComponent.new(trigger_text: "Click me", text_content: "Popover content"))
    assert_includes rendered_content, "Click me"
  end

  test "renders plain text content escaped" do
    render_inline(PopoverComponent.new(trigger_text: "Trigger", text_content: "<script>alert('xss')</script>"))
    assert_includes rendered_content, "&lt;script&gt;"
  end

  test "renders HTML content without escaping" do
    html_content = "<strong>Bold text</strong>"
    render_inline(PopoverComponent.new(trigger_text: "Trigger", html_content: html_content))
    assert_includes rendered_content, "<strong>Bold text</strong>"
  end

  test "popover hidden by default and shown on hover" do
    render_inline(PopoverComponent.new(trigger_text: "Trigger", text_content: "Content"))
    assert_includes rendered_content, "group-hover:block"
    assert_includes rendered_content, "hidden"
  end

  test "applies custom CSS classes to trigger" do
    render_inline(PopoverComponent.new(trigger_text: "Trigger", text_content: "Content", css_classes: "text-blue-500"))
    assert_includes rendered_content, "text-blue-500"
  end
end
