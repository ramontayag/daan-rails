# lib/daan/workspace.rb
module Daan
  class Workspace
    attr_reader :root

    def initialize(path)
      @root = Pathname.new(path).expand_path
    end

    # Resolves a relative path within this workspace.
    # Raises ArgumentError if the resolved path escapes the workspace root.
    def resolve(relative_path)
      full = (@root / relative_path).expand_path
      unless full.to_s.start_with?("#{@root}/") || full == @root
        raise ArgumentError, "Path '#{relative_path}' escapes workspace"
      end
      full
    end

    def mkdir_p
      FileUtils.mkdir_p(@root)
    end

    def to_s = @root.to_s
    def to_str = @root.to_s
  end
end
