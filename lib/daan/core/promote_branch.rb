require "open3"

module Daan
  module Core
    class PromoteBranch < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 1.minute

      if Rails.env.development?
        description "Promote a feature branch to the running development app. " \
                    "Merges the branch into develop in your workspace clone, pushes develop to origin, " \
                    "then pulls the latest develop into the running app and reloads agent definitions."
      else
        description "Promote a feature branch to production by opening a pull request against main. " \
                    "Call this after pushing your branch to origin."
      end

      param :branch, desc: "The feature branch name to promote (e.g. 'feature/add-qa-agent'). " \
                           "Must be pushed to origin first."
      param :repo_path, desc: "Path to the cloned repo in your workspace where the merge should happen " \
                              "(e.g. 'daan-rails'). Relative to workspace root. Required in development.", required: false
      param :tests_passed, desc: "Confirm you ran `bin/ci` in the " \
                                 "cloned repo and all checks passed. Must be true to promote."
      param :title, desc: "Pull request title (production only).", required: false
      param :body,  desc: "Pull request body (production only).", required: false

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
        @workspace = workspace
      end

      def execute(branch:, tests_passed:, repo_path: nil, title: nil, body: nil)
        raise "Tests must pass before promoting. Run `bin/ci` first." unless tests_passed
        if development?
          promote_to_development(branch, repo_path)
        else
          promote_to_production(branch, title, body)
        end
      end

      private

      def development?
        Rails.env.development?
      end

      def promote_to_development(branch, repo_path)
        raise "repo_path is required in development mode" unless repo_path
        clone_dir = @workspace ? File.join(@workspace.root.to_s, repo_path) : repo_path
        app_root = Rails.root.to_s

        # Stage 1: merge feature branch into develop in the workspace clone
        run!(%w[git fetch origin], clone_dir)

        unless branch_exists_in_origin?(branch, clone_dir)
          raise "Branch '#{branch}' not found in origin remote.\n\n" \
                "Push it to GitHub first with:\n" \
                "  git push origin #{branch}\n\n" \
                "Then try PromoteBranch again."
        end

        unless branch_already_merged?(branch, clone_dir)
          unless branch_based_on_main?(branch, clone_dir)
            raise "Branch '#{branch}' is not based on the latest origin/main.\n\n" \
                  "Rebase your branch onto origin/main first:\n" \
                  "  git fetch origin\n" \
                  "  git rebase origin/main\n" \
                  "  git push --force-with-lease origin #{branch}\n\n" \
                  "Then call PromoteBranch again."
          end

          run!(%w[git checkout develop], clone_dir)
          run!(%w[git reset --hard origin/develop], clone_dir)
          begin
            run!([ "git", "merge", "origin/#{branch}" ], clone_dir)
          rescue => e
            raise "Merge conflict merging origin/#{branch} into develop.\n\n" \
                  "The merge is still in progress in your clone at #{clone_dir}. " \
                  "Resolve the conflicts, then:\n" \
                  "  git add -A && git commit\n" \
                  "  git push origin develop\n\n" \
                  "Then call PromoteBranch again — it will see the branch is merged and sync the running app.\n\n" \
                  "Original error: #{e.message}"
          end
          run!(%w[git push origin develop], clone_dir)
        end

        # Stage 2: pull latest develop into the running app
        run!(%w[git fetch origin], app_root)
        run!(%w[git checkout develop], app_root)
        run!(%w[git reset --hard origin/develop], app_root)

        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        override_dir = Rails.root.join("config/agents")
        Daan::AgentLoader.sync!(override_dir) if override_dir.exist?

        "Promoted '#{branch}' to development and reloaded agent definitions. " \
        "Branch is in origin — open a pull request when ready for production."
      end

      def promote_to_production(branch, title, body)
        app_root = Rails.root.to_s
        cmd = [ "gh", "pr", "create", "--base", "main", "--head", branch ]
        cmd += [ "--title", title ] if title
        cmd += [ "--body", body || "" ]

        stdout, stderr, status = Open3.capture3(*cmd, chdir: app_root)
        raise "gh pr create failed: #{stderr}" unless status.success?
        stdout.strip
      end

      def branch_exists_in_origin?(branch, app_root)
        stdout, _stderr, status = Open3.capture3("git", "ls-remote", "origin", "refs/heads/#{branch}", chdir: app_root)
        status.success? && !stdout.strip.empty?
      end

      def branch_based_on_main?(branch, dir)
        _, _, status = Open3.capture3("git", "merge-base", "--is-ancestor", "origin/main", "origin/#{branch}", chdir: dir)
        status.success?
      end

      def branch_already_merged?(branch, dir)
        origin_hash, _, s1 = Open3.capture3("git", "rev-parse", "origin/#{branch}", chdir: dir)
        _develop_hash, _, s2 = Open3.capture3("git", "rev-parse", "origin/develop", chdir: dir)
        return false unless s1.success? && s2.success?

        merge_base, _, s3 = Open3.capture3("git", "merge-base", "origin/develop", "origin/#{branch}", chdir: dir)
        return false unless s3.success?

        origin_hash.strip == merge_base.strip
      end

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return if status.success?
        output = [ stdout, stderr ].reject(&:empty?).join("\n")
        raise "#{cmd.join(" ")} failed (exit #{status.exitstatus}): #{output}"
      end
    end
  end
end
