require "test_helper"
require "minitest/mock"

class Daan::Core::MergeBranchToSelfTest < ActiveSupport::TestCase
  def setup
    @tool = Daan::Core::MergeBranchToSelf.new
    @app_root = Rails.root.to_s
  end

  test "raises clear error when branch does not exist in origin" do
    @tool.stub :branch_exists_in_origin?, false do
      error = assert_raises(RuntimeError) do
        @tool.execute(branch: "nonexistent-branch")
      end
      
      assert_includes error.message, "Branch 'nonexistent-branch' not found in origin remote"
      assert_includes error.message, "git push origin nonexistent-branch"
      assert_includes error.message, "Then try MergeBranchToSelf again"
    end
  end

  test "returns friendly message when branch is already merged" do
    @tool.stub :branch_exists_in_origin?, true do
      @tool.stub :branch_already_merged?, true do
        result = @tool.execute(branch: "already-merged-branch")
        
        assert_equal "Branch 'already-merged-branch' is already merged into develop. No action needed.", result
      end
    end
  end

  test "provides helpful error context for merge failures" do
    @tool.stub :branch_exists_in_origin?, true do
      @tool.stub :branch_already_merged?, false do
        @tool.stub :run!, ->(*args) { raise "merge conflict" } do
          error = assert_raises(RuntimeError) do
            @tool.execute(branch: "conflicting-branch")
          end
          
          assert_includes error.message, "Failed to merge origin/conflicting-branch into develop"
          assert_includes error.message, "Merge conflicts that need manual resolution"
          assert_includes error.message, "Branch has diverged from develop"
          assert_includes error.message, "Original error: merge conflict"
        end
      end
    end
  end

  test "branch_exists_in_origin? detects existing branch" do
    # Mock successful git ls-remote output
    mock_output = "abc123\trefs/heads/existing-branch\n"
    Open3.stub :capture3, [mock_output, "", OpenStruct.new(success?: true)] do
      assert @tool.send(:branch_exists_in_origin?, "existing-branch", @app_root)
    end
  end

  test "branch_exists_in_origin? detects missing branch" do
    # Mock empty git ls-remote output (branch doesn't exist)
    Open3.stub :capture3, ["", "", OpenStruct.new(success?: true)] do
      refute @tool.send(:branch_exists_in_origin?, "missing-branch", @app_root)
    end
  end

  test "branch_already_merged? detects already merged branch" do
    # Mock scenario where branch is already merged
    branch_hash = "abc123\n"
    merge_base_hash = "abc123\n"
    
    Open3.stub :capture3, lambda { |*args|
      case args
      when ["git", "rev-parse", "origin/merged-branch", { chdir: @app_root }]
        [branch_hash, "", OpenStruct.new(success?: true)]
      when ["git", "rev-parse", "develop", { chdir: @app_root }]
        ["def456\n", "", OpenStruct.new(success?: true)]
      when ["git", "merge-base", "develop", "origin/merged-branch", { chdir: @app_root }]
        [merge_base_hash, "", OpenStruct.new(success?: true)]
      end
    } do
      assert @tool.send(:branch_already_merged?, "merged-branch", @app_root)
    end
  end

  test "branch_already_merged? detects unmerged branch" do
    # Mock scenario where branch is not merged
    branch_hash = "abc123\n"
    merge_base_hash = "def456\n"
    
    Open3.stub :capture3, lambda { |*args|
      case args
      when ["git", "rev-parse", "origin/unmerged-branch", { chdir: @app_root }]
        [branch_hash, "", OpenStruct.new(success?: true)]
      when ["git", "rev-parse", "develop", { chdir: @app_root }]
        ["ghi789\n", "", OpenStruct.new(success?: true)]
      when ["git", "merge-base", "develop", "origin/unmerged-branch", { chdir: @app_root }]
        [merge_base_hash, "", OpenStruct.new(success?: true)]
      end
    } do
      refute @tool.send(:branch_already_merged?, "unmerged-branch", @app_root)
    end
  end
end