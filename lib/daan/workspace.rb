# lib/daan/workspace.rb
module Daan
  class Workspace
    attr_reader :root

    def initialize(path)
      @root = Pathname.new(path).expand_path
    end

    # Resolves a relative path within this workspace.
    # Raises ArgumentError if the path escapes the workspace root,
    # including via symlinks or null bytes.
    def resolve(relative_path)
      raise ArgumentError, "Path contains null byte" if relative_path.to_s.include?("\0")

      absolute = @root / relative_path

      # Walk up to the deepest existing ancestor and realpath it, then
      # re-append the non-existent suffix. Catches symlink escapes for
      # both existing files and not-yet-created paths (e.g. Write tool).
      suffix = []
      candidate = absolute
      until candidate.exist?
        suffix.unshift(candidate.basename.to_s)
        candidate = candidate.dirname
      end
      real = Pathname.new(File.realpath(candidate)).join(*suffix)

      unless real.to_s.start_with?("#{@root}/") || real == @root
        raise ArgumentError, "Path '#{relative_path}' escapes workspace"
      end
      real
    end

    def to_s = @root.to_s
  end
end
