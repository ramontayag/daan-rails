# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_steps,
                     :workspace, :base_tools, :delegates_to, :hook_names,
                     keyword_init: true) do
    def initialize(**)
      super
      self.base_tools       ||= []
      self.delegates_to     ||= []
      self.hook_names       ||= []
    end

    def tools(chat: nil)
      all_kwargs = { workspace: workspace, chat: chat, storage: Daan::Memory.storage,
                     agent_name: name }
      base_tools.map do |t|
        accepted = t.instance_method(:initialize).parameters.map(&:last)
        t.new(**all_kwargs.slice(*accepted)).tap do |instance|
          instance.singleton_class.prepend(Core::SafeExecute)
          instance.singleton_class.prepend(Core::HookDispatch)
        end
      end
    end

    def to_param
      name
    end

    def busy?
      Chat.in_progress.exists?(agent_name: name)
    end

    def max_steps_reached?(step_count)
      step_count >= max_steps
    end
  end
end
