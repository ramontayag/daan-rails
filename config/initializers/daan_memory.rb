# Monkey-patch: FilesystemAdapter#write uses File.write for binary .emb files (embedding
# vectors produced by pack("f*")), which returns an ASCII-8BIT string. In a Rails
# environment Encoding.default_internal is set to UTF-8, causing File.write to attempt a
# transcoding that raises Encoding::UndefinedConversionError. Plain Ruby leaves
# default_internal nil so no transcoding occurs — making the bug non-reproducible outside
# Rails without explicitly setting Encoding.default_internal = UTF-8.
# The fix is to use File.binwrite, which skips transcoding regardless of encoding defaults.
#
# Upstream issue: https://github.com/parruda/swarm/issues/191
SwarmMemory::Adapters::FilesystemAdapter.prepend(Module.new do
  def write(file_path:, content:, title:, embedding: nil, metadata: nil)
    # Delegate to super without embedding so it skips the buggy File.write call on line 125.
    # We then write the embedding ourselves using File.binwrite.
    result = super(file_path: file_path, content: content, title: title,
                   embedding: nil, metadata: metadata)

    if embedding
      base_path = file_path.sub(/\.md\z/, "")
      emb_file = File.join(@directory, "#{flatten_path(base_path)}.emb")
      File.binwrite(emb_file, embedding.pack("f*"))
    end

    result
  end
end)

# Boot the shared memory storage. The ONNX model loads on first embed call, not here.
Rails.application.config.after_initialize do
  Daan::Core::Memory.storage
end
