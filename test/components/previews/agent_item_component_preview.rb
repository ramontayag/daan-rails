class AgentItemComponentPreview < ViewComponent::Preview
  # Agent is idle — green dot
  def idle
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff")
    agent.define_singleton_method(:busy?) { false }
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is busy on a task — yellow dot
  def busy
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff")
    agent.define_singleton_method(:busy?) { true }
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is selected (current conversation) — highlighted background
  def active
    agent = Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff")
    agent.define_singleton_method(:busy?) { false }
    render AgentItemComponent.new(agent: agent, active: true)
  end
end
