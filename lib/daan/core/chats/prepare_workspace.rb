module Daan
  module Core
    module Chats
    class PrepareWorkspace
      def self.call(agent)
        agent.workspace&.root&.mkpath
      end
    end
    end
  end
end
