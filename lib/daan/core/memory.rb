module Daan
  module Core
    module Memory
    # Thread-safe: @storage is set at boot by the initializer before Puma spawns threads.
    def self.storage
      @storage ||= SwarmMemory::Core::Storage.new(
        adapter: SwarmMemory::Adapters::FilesystemAdapter.new(
          directory: Rails.root.join("storage/memory").to_s
        ),
        embedder: SwarmMemory::Embeddings::InformersEmbedder.new
      )
    end
    end
  end
end
