module Daan
  module Core
    module Chats
    class ConfigureLlm
      def self.call(chat, agent)
        system_prompt = BuildSystemPrompt.call(chat, agent)

        chat
          .with_model(agent.model_name)
          .with_instructions(system_prompt)
          .with_tools(*agent.tools(chat: chat))
      end
    end
    end
  end
end
