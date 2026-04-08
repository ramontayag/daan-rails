require "open3"

module Daan
  module Core
    module Hooks
      class BranchFreshness
        include Daan::Core::Hook.module(applies_to: [ Daan::Core::Bash ])

        def after_tool_call(chat:, tool_name:, args:, result:)
          commands = args[:commands]
          return unless commands.is_a?(Array)
          return unless commands.any? { |cmd| cmd.is_a?(Array) && cmd[0] == "git" && cmd[1] == "checkout" && cmd[2] == "-b" }

          agent = Daan::Core::AgentRegistry.find(chat.agent_name)
          return unless agent&.workspace

          dir = args[:path] ? agent.workspace.resolve(args[:path]) : agent.workspace.root
          branch = default_branch(dir)

          if fetch_origin(dir)
            return if based_on_latest?(branch, dir)
          end

          chat.messages.create!(
            role: "user",
            content: "#{Daan::Core::SystemTag::PREFIX} New branch created but it is not based on the latest origin/#{branch}. " \
                     "Run: git fetch origin && git rebase origin/#{branch}",
            visible: false
          )
        end

        private

        def default_branch(dir)
          stdout, _, status = Open3.capture3("git", "symbolic-ref", "refs/remotes/origin/HEAD", chdir: dir.to_s)
          if status.success?
            stdout.strip.sub("refs/remotes/origin/", "")
          else
            "main"
          end
        end

        def fetch_origin(dir)
          _, _, status = Open3.capture3("git", "fetch", "origin", chdir: dir.to_s)
          status.success?
        end

        def based_on_latest?(branch, dir)
          _, _, status = Open3.capture3("git", "merge-base", "--is-ancestor", "origin/#{branch}", "HEAD", chdir: dir.to_s)
          status.success?
        end
      end
    end
  end
end
