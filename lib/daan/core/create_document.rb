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
        "Document created with id=#{doc.id}"
      end
    end
  end
end
