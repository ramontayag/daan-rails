# lib/daan/core/report_back.rb
module Daan
  module Core
    class ReportBack < RubyLLM::Tool
      description "Report your results back to the delegating agent"
      param :message, desc: "Your findings or results to report"

      def initialize(workspace: nil, chat: nil)
        @chat = chat
      end

      def execute(message:)
        parent_chat = @chat.parent_chat
        raise "No parent chat — this thread was not created by delegation" unless parent_chat

        current_agent = Daan::AgentRegistry.find(@chat.agent_name)
        Daan::CreateMessage.call(parent_chat, role: "user",
                                 content: "#{current_agent.display_name}: #{message}",
                                 visible: false)

        parent_agent = Daan::AgentRegistry.find(parent_chat.agent_name)
        "Report sent to #{parent_agent.display_name}."
      end
    end
  end
end
