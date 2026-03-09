# lib/daan/core/read.rb
module Daan
  module Core
    class Read < RubyLLM::Tool
      description "Read a file from the workspace"
      param :path, desc: "Relative path to the file"

      def execute(path:)
        file = Pathname.new(self.class.workspace) / path
        raise "File not found: #{path}" unless file.exist?
        file.read
      end
    end
  end
end
