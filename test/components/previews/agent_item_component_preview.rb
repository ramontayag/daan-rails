class AgentItemComponentPreview < ViewComponent::Preview
  # Agent is idle — green dot
  def idle
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_steps: 10)
    agent.define_singleton_method(:busy?) { false }
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is busy on a task — yellow dot
  def busy
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_steps: 10)
    agent.define_singleton_method(:busy?) { true }
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is selected (current conversation) — highlighted background
  def active
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_steps: 10)
    agent.define_singleton_method(:busy?) { false }
    render AgentItemComponent.new(agent: agent, active: true)
  end
end
