module Daan
  module Memory
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
