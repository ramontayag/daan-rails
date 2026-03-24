# lib/daan/chats/enqueue_compaction.rb
module Daan
  module Chats
    class EnqueueCompaction
      def self.call(chat)
        context_window = chat.model.context_window
        threshold = (context_window * 0.8).to_i
        # Integer division in COALESCE fallback is intentional — rough estimate,
        # 80% threshold provides sufficient headroom.
        token_sum = Message.active
                           .where(chat_id: chat.id)
                           .sum("COALESCE(output_tokens, LENGTH(content) / 4, 0)")
        CompactJob.perform_later(chat) if token_sum >= threshold
      end
    end
  end
end
