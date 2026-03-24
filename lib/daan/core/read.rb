# lib/daan/core/read.rb
module Daan
  module Core
    class Read < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      DEFAULT_LINE_LIMIT = 2000

      description "Read a file from the workspace"
      param :path, desc: "Relative path to the file"
      param :start_line, desc: "First line to read (1-indexed, default: 1)", required: false
      param :end_line, desc: "Last line to read (inclusive, default: start_line + #{DEFAULT_LINE_LIMIT - 1})", required: false

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @workspace = workspace
      end

      def execute(path:, start_line: nil, end_line: nil)
        lines = @workspace.resolve(path).readlines
        total = lines.length

        first = (start_line&.to_i || 1).clamp(1, [ total, 1 ].max)
        last  = (end_line&.to_i   || first + DEFAULT_LINE_LIMIT - 1).clamp(first, total)

        result = lines[(first - 1)..(last - 1)].join

        if end_line.nil? && last < total
          result += "\n[File truncated: showing lines #{first}-#{last} of #{total}. Pass start_line/end_line to read more.]"
        end

        result
      end
    end
  end
end
