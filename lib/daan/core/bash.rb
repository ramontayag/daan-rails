require "open3"

module Daan
  module Core
    class Bash < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

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

      DENIED_BINARIES = %w[sh bash zsh dash ksh csh tcsh fish].freeze

      def initialize(workspace: nil, chat: nil, allowed_commands: Daan::Core.configuration.allowed_commands, **)
        @workspace        = workspace
        @allowed_commands = allowed_commands
      end

      def execute(commands:, path: nil)
        commands = JSON.parse(commands) if commands.is_a?(String)
        return "" if commands.empty?

        dir = path ? @workspace.resolve(path) : @workspace.root

        outputs = commands.map do |cmd|
          binary = cmd.first
          if DENIED_BINARIES.include?(binary)
            raise "shell interpreter '#{binary}' is not allowed"
          end
          unless @allowed_commands.include?(binary)
            raise "command '#{binary}' is not allowed. Permitted: #{@allowed_commands.join(', ')}"
          end

          validate_path_args!(cmd[1..], dir)
          run_command(cmd, dir: dir)
        end

        outputs.join("\n")
      end

      private

      def validate_path_args!(args, cwd)
        args.each do |arg|
          raise ArgumentError, "Argument contains null byte" if arg.include?("\0")

          value = if arg.start_with?("-") && arg.include?("=")
            arg.split("=", 2).last
          elsif arg.start_with?("-")
            next
          else
            arg
          end

          next unless looks_like_path?(value, cwd)

          expanded = File.expand_path(value, cwd)
          resolved = File.exist?(expanded) ? File.realpath(expanded) : expanded
          root = @workspace.root.to_s

          unless resolved.start_with?("#{root}/") || resolved == root
            raise ArgumentError, "Argument '#{arg}' escapes workspace"
          end
        end
      end

      def looks_like_path?(arg, cwd)
        arg.start_with?("/") || arg.include?("..") || arg.include?("/") ||
          File.exist?(File.join(cwd.to_s, arg))
      end

      def run_command(cmd, dir:)
        env = { "GIT_TERMINAL_PROMPT" => "0" }
        stdout_str = +""; stderr_str = +""

        # Non-block form so we control cleanup; the block form's ensure calls
        # wait_thr.join unconditionally, which would re-introduce the hang.
        stdin_io, stdout_io, stderr_io, wait_thr =
          Open3.popen3(env, *cmd, chdir: dir.to_s, pgroup: true)
        stdin_io.close

        drain = ->(io, buf) do
          buf << io.read
        rescue IOError, Errno::EBADF
          # pipe closed by timeout handler — we're done
        end

        out_thread = Thread.new { drain.call(stdout_io, stdout_str) }
        err_thread = Thread.new { drain.call(stderr_io, stderr_str) }

        begin
          out_thread.join; err_thread.join
          wait_thr.join
        rescue Timeout::Error
          pid = wait_thr.pid
          Process.kill("KILL", pid) rescue nil   # kill the direct child
          Process.kill("KILL", -pid) rescue nil  # kill its process group
          stdout_io.close rescue nil             # unblock drain threads via IOError
          stderr_io.close rescue nil
          raise "#{cmd.join(' ')} timed out"
        ensure
          stdout_io.close rescue nil
          stderr_io.close rescue nil
        end

        status = wait_thr.value

        unless status.success?
          output = [ stdout_str, stderr_str ].reject(&:empty?).join("\n")
          raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
        end

        combined = [ stdout_str, stderr_str ].reject(&:empty?).join("\n")
        "$ #{cmd.join(' ')}\n#{combined}"
      end
    end
  end
end
