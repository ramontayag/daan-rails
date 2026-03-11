# lib/daan/core/read.rb
module Daan
  module Core
    class Read < RubyLLM::Tool
      description "Read a file from the workspace"
      param :path, desc: "Relative path to the file"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @workspace = workspace
      end

      def execute(path:)
        @workspace.resolve(path).read
      end
    end
  end
end
