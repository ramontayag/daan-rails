class ComposeBarComponentPreview < ViewComponent::Preview
  def default
    agent = Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_turns: 10)
    render ComposeBarComponent.new(agent: agent)
  end
end
