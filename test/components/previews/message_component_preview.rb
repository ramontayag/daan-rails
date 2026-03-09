class MessageComponentPreview < ViewComponent::Preview
  # Human sends a short message
  def user_message
    render MessageComponent.new(role: "user", body: "Hello, what can you help me with today?")
  end

  # Agent responds
  def assistant_message
    render MessageComponent.new(role: "assistant",
      body: "I'm the Chief of Staff. I can coordinate tasks and answer questions.")
  end

  # A long response that wraps
  def long_assistant_message
    render MessageComponent.new(role: "assistant",
      body: "This is a longer response that demonstrates how the bubble handles wrapping. " \
            "It should stay within max-w-lg and remain readable regardless of content length. " \
            "The padding and border-radius should stay consistent throughout.")
  end
end
