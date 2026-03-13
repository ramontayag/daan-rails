require "open3"

module Daan
  module Core
    class MergeBranchToSelf < RubyLLM::Tool
      description "Merge a feature branch into the develop branch of the running app and " \
                  "hot-reload agent definitions. Call this after pushing a self-modification " \
                  "branch to see changes immediately. Only use in development."
      param :branch, desc: "The feature branch name to merge into develop (e.g. 'feature/add-qa-agent'). " \
                           "IMPORTANT: Branch must be pushed to GitHub origin first with 'git push origin <branch-name>'"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
      end

      def execute(branch:)
        app_root = Rails.root.to_s
        
        # Fetch latest from origin
        run!(%w[git fetch origin], app_root)
        
        # Check if branch exists in origin before attempting merge
        unless branch_exists_in_origin?(branch, app_root)
          raise "Branch '#{branch}' not found in origin remote.\n\n" \
                "Push it to GitHub first with:\n" \
                "  git push origin #{branch}\n\n" \
                "Then try MergeBranchToSelf again."
        end
        
        # Check if branch is already merged
        if branch_already_merged?(branch, app_root)
          return "Branch '#{branch}' is already merged into develop. No action needed."
        end
        
        # Perform the merge
        run!(%w[git checkout develop], app_root)
        begin
          run!(["git", "merge", "origin/#{branch}"], app_root)
        rescue => e
          # Provide better context for merge failures
          raise "Failed to merge origin/#{branch} into develop.\n\n" \
                "This might be due to:\n" \
                "- Merge conflicts that need manual resolution\n" \
                "- Branch has diverged from develop\n" \
                "- Git repository is in an inconsistent state\n\n" \
                "Original error: #{e.message}\n\n" \
                "Try resolving conflicts manually or contact support."
        end
        
        # Reload agent definitions
        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        override_dir = Rails.root.join("config/agents")
        Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
        
        "Merged origin/#{branch} into develop and reloaded agent definitions."
      end

      private

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return if status.success?
        output = [stdout, stderr].reject(&:empty?).join("\n")
        raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
      end
      
      def branch_exists_in_origin?(branch, app_root)
        stdout, stderr, status = Open3.capture3("git", "ls-remote", "origin", "refs/heads/#{branch}", chdir: app_root)
        status.success? && !stdout.strip.empty?
      end
      
      def branch_already_merged?(branch, app_root)
        # Get commit hashes for comparison
        origin_branch_hash, _, status1 = Open3.capture3("git", "rev-parse", "origin/#{branch}", chdir: app_root)
        develop_hash, _, status2 = Open3.capture3("git", "rev-parse", "develop", chdir: app_root)
        
        # If either command fails, assume not merged (let merge attempt handle errors)
        return false unless status1.success? && status2.success?
        
        # Check if the branch commit is already in develop's history
        merge_base, _, status3 = Open3.capture3("git", "merge-base", "develop", "origin/#{branch}", chdir: app_root)
        return false unless status3.success?
        
        # If merge-base equals the branch commit, branch is already merged
        origin_branch_hash.strip == merge_base.strip
      end
    end
  end
end