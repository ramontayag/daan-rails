# lib/daan/core/write.rb
module Daan
  module Core
    class Write < RubyLLM::Tool
      description "Write content to a file in the workspace"
      param :path, desc: "Relative path to the file"
      param :content, desc: "The content to write"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @workspace = workspace
      end

      def execute(path:, content:)
        file = @workspace.resolve(path)
        file.dirname.mkpath
        file.write(content)
        "Written #{content.bytesize} bytes to #{path}"
      end
    end
  end
end
