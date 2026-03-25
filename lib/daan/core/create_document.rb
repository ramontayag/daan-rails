# lib/daan/core/create_document.rb
module Daan
  module Core
    class CreateDocument < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 5.seconds

      description "Create a new document in this thread"
      param :title, desc: "Title of the document"
      param :body, desc: "Markdown content of the document"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @chat = chat
      end

      def execute(title:, body:)
        doc = @chat.documents.create!(title: title, body: body)
        broadcast_document_panel
        "Document created with id=#{doc.id}"
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
