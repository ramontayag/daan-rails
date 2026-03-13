require "open3"

module Daan
  module Core
    class PromoteBranch < RubyLLM::Tool
      if Rails.env.development?
        description "Promote a feature branch to the running development app. " \
                    "Merges the branch into develop and hot-reloads agent definitions so changes are " \
                    "immediately visible. The branch stays in origin and can be promoted to production " \
                    "later by opening a pull request."
      else
        description "Promote a feature branch to production by opening a pull request against main. " \
                    "Call this after pushing your branch to origin."
      end

      param :branch, desc: "The feature branch name to promote (e.g. 'feature/add-qa-agent'). " \
                           "Must be pushed to origin first."
      param :title, desc: "Pull request title (production only).", required: false
      param :body,  desc: "Pull request body (production only).", required: false

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
      end

      def execute(branch:, title: nil, body: nil)
        if development?
          promote_to_development(branch)
        else
          promote_to_production(branch, title, body)
        end
      end

      private

      def development?
        Rails.env.development?
      end

      def promote_to_development(branch)
        app_root = Rails.root.to_s

        run!(%w[git fetch origin], app_root)

        unless branch_exists_in_origin?(branch, app_root)
          raise "Branch '#{branch}' not found in origin remote.\n\n" \
                "Push it to GitHub first with:\n" \
                "  git push origin #{branch}\n\n" \
                "Then try PromoteBranch again."
        end

        if branch_already_merged?(branch, app_root)
          return "Branch '#{branch}' is already merged into develop. No action needed."
        end

        run!(%w[git checkout develop], app_root)
        run!(["git", "merge", "--ff-only", "origin/main"], app_root) rescue nil
        begin
          run!(["git", "merge", "origin/#{branch}"], app_root)
        rescue => e
          raise "Failed to merge origin/#{branch} into develop.\n\n" \
                "This might be due to:\n" \
                "- Merge conflicts that need manual resolution\n" \
                "- Branch has diverged from develop\n" \
                "- Git repository is in an inconsistent state\n\n" \
                "Original error: #{e.message}"
        end

        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        override_dir = Rails.root.join("config/agents")
        Daan::AgentLoader.sync!(override_dir) if override_dir.exist?

        "Promoted '#{branch}' to development and reloaded agent definitions. " \
        "Branch is in origin — open a pull request when ready for production."
      end

      def promote_to_production(branch, title, body)
        app_root = Rails.root.to_s
        cmd = ["gh", "pr", "create", "--base", "main", "--head", branch]
        cmd += ["--title", title] if title
        cmd += ["--body", body || ""]

        stdout, stderr, status = Open3.capture3(*cmd, chdir: app_root)
        raise "gh pr create failed: #{stderr}" unless status.success?
        stdout.strip
      end

      def branch_exists_in_origin?(branch, app_root)
        stdout, _stderr, status = Open3.capture3("git", "ls-remote", "origin", "refs/heads/#{branch}", chdir: app_root)
        status.success? && !stdout.strip.empty?
      end

      def branch_already_merged?(branch, app_root)
        origin_hash, _, s1 = Open3.capture3("git", "rev-parse", "origin/#{branch}", chdir: app_root)
        _develop_hash, _, s2 = Open3.capture3("git", "rev-parse", "develop", chdir: app_root)
        return false unless s1.success? && s2.success?

        merge_base, _, s3 = Open3.capture3("git", "merge-base", "develop", "origin/#{branch}", chdir: app_root)
        return false unless s3.success?

        origin_hash.strip == merge_base.strip
      end

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return if status.success?
        output = [stdout, stderr].reject(&:empty?).join("\n")
        raise "#{cmd.join(" ")} failed (exit #{status.exitstatus}): #{output}"
      end
    end
  end
end
