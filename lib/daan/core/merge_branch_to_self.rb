# lib/daan/core/merge_branch_to_self.rb
require "open3"

module Daan
  module Core
    class MergeBranchToSelf < RubyLLM::Tool
      description "Merge a feature branch into the develop branch of the running app and " \
                  "hot-reload agent definitions. Call this after pushing a self-modification " \
                  "branch to see changes immediately. Only use in development."
      param :branch, desc: "The feature branch name to merge into develop (e.g. 'feature/add-qa-agent')"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
      end

      def execute(branch:)
        app_root = Rails.root.to_s
        run!(%w[git fetch origin], app_root)
        run!(%w[git checkout develop], app_root)
        run!([ "git", "merge", "origin/#{branch}" ], app_root)
        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        override_dir = Rails.root.join("config/agents")
        Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
        "Merged origin/#{branch} into develop and reloaded agent definitions."
      end

      private

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return if status.success?
        output = [ stdout, stderr ].reject(&:empty?).join("\n")
        raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
      end
    end
  end
end
