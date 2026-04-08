module Daan
  module Core
    # Extracts the pricing hash from a RubyLLM::Model::Info in the format stored
    # by ruby_llm:load_models (i.e. what ends up in the models.pricing DB column).
    #
    # Use this instead of calling model_info.pricing.to_h or .to_json directly —
    # those two return different structures, and .to_json is wrong for our purposes.
    class RubyLlmModelPricing
    def self.call(model_info)
      JSON.parse(model_info.pricing.to_h.to_json)
    end
    end
  end
end
