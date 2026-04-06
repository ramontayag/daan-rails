require "test_helper"

class AgentItemComponentMarkdownTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  def agent_with_description(description)
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "test_agent",
        display_name: "Test Agent",
        description: description,
        model_name: "claude-3-5-haiku-20241022",
        system_prompt: "p",
        max_steps: 10
      )
    )
    Daan::AgentRegistry.find("test_agent")
  end

  test "renders agent without description as plain text" do
    agent = agent_with_description("")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "Test Agent"
    assert_not_includes rendered_content, "PopoverComponent"
  end

  test "renders agent with description using popover" do
    agent = agent_with_description("A test **agent**")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "<strong>agent</strong>"
  end

  test "renders markdown bold in description" do
    agent = agent_with_description("This is **bold** text")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "<strong>bold</strong>"
  end

  test "renders markdown italic in description" do
    agent = agent_with_description("This is *italic* text")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "<em>italic</em>"
  end

  test "renders markdown code in description" do
    agent = agent_with_description("Use `code` here")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "<code>code</code>"
  end

  test "renders markdown links in description" do
    agent = agent_with_description("Check [this](https://example.com)")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, '<a href="https://example.com"'
    assert_includes rendered_content, ">this</a>"
  end

  test "renders fenced code blocks in description" do
    description = "```ruby\ncode = true\n```"
    agent = agent_with_description(description)
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "<pre>"
    assert_includes rendered_content, "<code"
  end

  test "popover has hover styling on agent name" do
    agent = agent_with_description("A test description")
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "hover:underline"
  end
end
