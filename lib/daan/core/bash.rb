require "open3"

module Daan
  module Core
    class Bash < RubyLLM::Tool
      description "Run one or more commands in the workspace. Each command is an array of " \
                  "strings: the binary plus its arguments. Commands run sequentially in the " \
                  "specified directory. Only binaries listed in allowed_commands may be used. " \
                  "If any command fails, an error is raised and no output is returned."
      param :commands, desc: "Commands to run, each as [binary, arg1, arg2, ...]. " \
                             "Example: [[\"git\", \"add\", \"-A\"], [\"git\", \"commit\", \"-m\", \"msg\"]]"
      param :path,     desc: "Working directory relative to workspace (optional, defaults to workspace root)"

      def initialize(workspace: nil, chat: nil, allowed_commands: [], **)
        @workspace        = workspace
        @allowed_commands = allowed_commands
      end

      def execute(commands:, path: nil)
        return "" if commands.empty?

        dir = path ? @workspace.resolve(path) : @workspace.root

        outputs = commands.map do |cmd|
          binary = cmd.first
          unless @allowed_commands.include?(binary)
            raise "Command '#{binary}' is not allowed. Permitted: #{@allowed_commands.join(', ')}"
          end

          stdout, stderr, status = Open3.capture3(*cmd, chdir: dir.to_s)
          unless status.success?
            output = [ stdout, stderr ].reject(&:empty?).join("\n")
            raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
          end

          "$ #{cmd.join(' ')}\n#{stdout}"
        end

        outputs.join("\n")
      end
    end
  end
end
