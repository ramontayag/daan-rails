# lib/daan/core/update_document.rb
module Daan
  module Core
    class UpdateDocument < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 5.seconds)
      include Rails.application.routes.url_helpers

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
        return_to = chat_thread_path(@chat)
        href = document_path(doc, return_to_uri: return_to)
        title = ERB::Util.html_escape(doc.title)
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_document_#{doc.id}",
          html: %(<div id="chat_document_#{doc.id}" class="px-3 py-1.5 text-xs"><a href="#{href}" class="hover:text-blue-600 block" data-turbo-frame="_top">#{title}</a></div>)
        )
        "Document updated with id=#{doc.id}"
      end
    end
  end
end
