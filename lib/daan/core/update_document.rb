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
        broadcast_document_panel
        "Document updated with id=#{doc.id}"
      end

      private

      def broadcast_document_panel
        @chat.reload
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_documents_icon_#{@chat.id}",
          renderable: ChatDocumentIconComponent.new(chat: @chat, show_docs: true)
        )
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_document_panel",
          renderable: ChatDocumentPanelComponent.new(chat: @chat, show_docs: true)
        )
      end
    end
  end
end
