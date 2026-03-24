# lib/daan/chats/prepare_workspace.rb
module Daan
  module Chats
    class PrepareWorkspace
      def self.call(agent)
        agent.workspace&.root&.mkpath
      end
    end
  end
end
