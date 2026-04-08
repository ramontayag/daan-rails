require "gem_config"

module Daan
  module Core
    include GemConfig::Base

    with_configuration do
      has :allowed_commands, classes: Array, default: [].freeze
    end
  end
end
