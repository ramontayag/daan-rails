class ChatCostComponentPreview < ViewComponent::Preview
  def self.setup_agents
    Daan::Core::AgentRegistry.find("chief_of_staff")
  rescue Daan::Core::AgentNotFoundError
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  def self.model_with_pricing
    Model.find_or_create_by!(model_id: "preview-model") do |m|
      m.name = "Preview Model"
      m.provider = "test"
      m.pricing = { "data" => { "text_tokens" => { "standard" => { "values" => {
        "input_per_million" => 3.0, "output_per_million" => 15.0, "cached_input_per_million" => 0.3
      } } } } }
    end
  end

  # No sub-chats — plain token/cost display
  def leaf_chat
    self.class.setup_agents
    model = self.class.model_with_pricing
    chat = Chat.create!(agent_name: "chief_of_staff", model: model)
    chat.messages.create!(role: "user", content: "hello", input_tokens: 12_000, output_tokens: 4_000, thinking_tokens: 0)
    render ChatCostComponent.new(chat: chat)
  end

  # No cost yet (zero tokens)
  def empty_chat
    self.class.setup_agents
    chat = Chat.create!(agent_name: "chief_of_staff")
    render ChatCostComponent.new(chat: chat)
  end

  # Parent chat with one sub-chat — shows total + breakdown toggle
  def parent_with_sub_chat
    self.class.setup_agents
    model = self.class.model_with_pricing
    parent = Chat.create!(agent_name: "chief_of_staff", model: model)
    child  = Chat.create!(agent_name: "developer", model: model, parent_chat: parent)
    parent.messages.create!(role: "user", content: "hello", input_tokens: 10_000, output_tokens: 3_000, thinking_tokens: 0)
    child.messages.create!(role: "user", content: "hi", input_tokens: 25_000, output_tokens: 8_000, thinking_tokens: 0)
    render ChatCostComponent.new(chat: parent)
  end
end
