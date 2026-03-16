require "open3"

module Daan
  module Core
    class Bash < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 120

      description "Run one or more commands in the workspace. Each command is an array of " \
                  "strings: the binary plus its arguments. Commands run sequentially in the " \
                  "specified directory. Only binaries listed in allowed_commands may be used. " \
                  "If any command fails, an error is raised and no output is returned."

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
          },
          "timeout" => {
            type: "number",
            description: "Seconds to wait per command before killing it (default: 30). Increase for slow network operations like git push/pull/clone."
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

      DEFAULT_TIMEOUT_SECONDS = 30

      def execute(commands:, path: nil, timeout: DEFAULT_TIMEOUT_SECONDS)
        commands = JSON.parse(commands) if commands.is_a?(String)
        return "" if commands.empty?

        dir = path ? @workspace.resolve(path) : @workspace.root

        outputs = commands.map do |cmd|
          binary = cmd.first
          unless @allowed_commands.include?(binary)
            raise "command '#{binary}' is not allowed. Permitted: #{@allowed_commands.join(', ')}"
          end

          run_command(cmd, dir: dir, timeout: timeout)
        end

        outputs.join("\n")
      end

      private

      def run_command(cmd, dir:, timeout:)
        env = { "GIT_TERMINAL_PROMPT" => "0" }
        stdout_str = +""; stderr_str = +""

        Open3.popen3(env, *cmd, chdir: dir.to_s) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          out_thread = Thread.new { stdout_str = stdout.read }
          err_thread = Thread.new { stderr_str = stderr.read }

          unless wait_thr.join(timeout)
            Process.kill("KILL", wait_thr.pid) rescue nil
            wait_thr.join
            out_thread.join; err_thread.join
            raise "#{cmd.join(' ')} timed out after #{timeout}s"
          end

          out_thread.join; err_thread.join
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
