require "swarm_memory"

# Boot the shared memory storage. The ONNX model loads on first embed call, not here.
Rails.application.config.after_initialize do
  Daan::Memory.storage
end
