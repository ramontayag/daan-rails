require "open3"

module Daan
  module Core
    class Bash < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Run one or more commands in the workspace. Each command is an array of " \
                  "strings: the binary plus its arguments. Commands run sequentially in the " \
                  "specified directory. Only binaries listed in allowed_commands may be used. " \
                  "If any command fails, an error is raised and no output is returned. " \
                  "Use timeout_seconds to increase the timeout for slow operations like test suites."

      params({
        type: "object",
        properties: {
          "commands" => {
            type: "array",
            description: %Q(Commands to run, each as [binary, arg1, arg2, ...]. Example: [["git", "add", "-A"], ["git", "commit", "-m", "msg"]]),
            items: { type: "array", items: { type: "string" } }
          },
          "path" => {
            type: "string",
            description: "Working directory relative to workspace (optional, defaults to workspace root)"
          }
        },
        required: [ "commands" ],
        additionalProperties: false,
        strict: true
      })

      def initialize(workspace: nil, chat: nil, allowed_commands: [], **)
        @workspace        = workspace
        @allowed_commands = allowed_commands
      end

      def execute(commands:, path: nil)
        commands = JSON.parse(commands) if commands.is_a?(String)
        return "" if commands.empty?

        dir = path ? @workspace.resolve(path) : @workspace.root

        outputs = commands.map do |cmd|
          binary = cmd.first
          unless @allowed_commands.include?(binary)
            raise "command '#{binary}' is not allowed. Permitted: #{@allowed_commands.join(', ')}"
          end

          run_command(cmd, dir: dir)
        end

        outputs.join("\n")
      end

      private

      def run_command(cmd, dir:)
        env = { "GIT_TERMINAL_PROMPT" => "0" }
        stdout_str = +""; stderr_str = +""

        Open3.popen3(env, *cmd, chdir: dir.to_s) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_thread = Thread.new { stdout_str = stdout.read rescue "" }
          err_thread = Thread.new { stderr_str = stderr.read rescue "" }

          begin
            out_thread.join; err_thread.join
            wait_thr.join
          rescue Timeout::Error
            Process.kill("KILL", wait_thr.pid) rescue nil
            wait_thr.join
            out_thread.join; err_thread.join
            raise "#{cmd.join(' ')} timed out"
          end

          status = wait_thr.value

          unless status.success?
            output = [ stdout_str, stderr_str ].reject(&:empty?).join("\n")
            raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
          end
        end

        combined = [ stdout_str, stderr_str ].reject(&:empty?).join("\n")
        "$ #{cmd.join(' ')}\n#{combined}"
      end
    end
  end
end
