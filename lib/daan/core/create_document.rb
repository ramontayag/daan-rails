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
        @chat.reload
        broadcast_new_document(doc)
        "Document created with id=#{doc.id}"
      end

      private

      def broadcast_new_document(doc)
        if @chat.documents.count == 1
          # First document — render the full icon structure for the first time
          Turbo::StreamsChannel.broadcast_replace_to(
            "chat_#{@chat.id}",
            target: "chat_documents_icon_#{@chat.id}",
            renderable: ChatDocumentIconComponent.new(chat: @chat)
          )
        else
          # Subsequent documents — stream into the open dropdown without closing it
          Turbo::StreamsChannel.broadcast_append_to(
            "chat_#{@chat.id}",
            target: "chat_documents_list_#{@chat.id}",
            html: "<div id=\"chat_document_#{doc.id}\" class=\"px-3 py-1.5 text-xs\">#{ERB::Util.html_escape(doc.title)}</div>"
          )
          Turbo::StreamsChannel.broadcast_replace_to(
            "chat_#{@chat.id}",
            target: "chat_documents_count_#{@chat.id}",
            html: "<span id=\"chat_documents_count_#{@chat.id}\" class=\"text-xs\">#{@chat.documents.count}</span>"
          )
        end
      end
    end
  end
end
