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
        doc = @chat.documents.find_by(id: id)
        return "No document with id=#{id} found in this thread." unless doc
        doc.update!(body: body)
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_document_#{doc.id}",
          html: "<div id=\"chat_document_#{doc.id}\" class=\"px-3 py-1.5 text-xs\">#{ERB::Util.html_escape(doc.title)}</div>"
        )
        "Document updated with id=#{doc.id}"
      end
    end
  end
end
