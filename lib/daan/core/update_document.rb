# lib/daan/core/update_document.rb
module Daan
  module Core
    class UpdateDocument < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 5.seconds

      description "Update the body of an existing document in this thread"
      param :id, desc: "ID of the document to update"
      param :body, desc: "New markdown content"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @chat = chat
      end

      def execute(id:, body:)
        doc = @chat.documents.find(id)
        doc.update!(body: body)
        "Document updated with id=#{doc.id}"
      end
    end
  end
end
