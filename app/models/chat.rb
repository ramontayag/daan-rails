class Chat < ApplicationRecord
  include AASM

  acts_as_chat messages_foreign_key: :chat_id

  belongs_to :parent_chat, class_name: "Chat", optional: true
  has_many :sub_chats, class_name: "Chat", foreign_key: :parent_chat_id,
                       dependent: :nullify, inverse_of: :parent_chat
  has_many :chat_steps, -> { order(:position) }, dependent: :destroy
  has_many :documents, dependent: :destroy

  validates :agent_name, presence: true

  aasm column: :task_status do
    state :pending, initial: true
    state :in_progress
    state :completed
    state :failed
    state :blocked

    event :start do
      transitions from: :pending, to: :in_progress
    end

    event :finish do
      transitions from: :in_progress, to: :completed
    end

    event :block do
      transitions from: :in_progress, to: :blocked
    end

    event :fail do
      transitions from: %i[pending in_progress], to: :failed
    end

    event :continue do
      transitions from: %i[completed blocked failed], to: :pending
    end
  end

  def self.conversation_partner_names_for(agent_name)
    my_chats = where(agent_name: agent_name)

    # Agents who delegated TO this agent (parents of this agent's chats)
    parent_names = where(id: my_chats.where.not(parent_chat_id: nil).select(:parent_chat_id))
                     .distinct.pluck(:agent_name)

    # Agents this agent delegated TO (children of this agent's chats)
    child_names = where(parent_chat: my_chats).distinct.pluck(:agent_name)

    (parent_names + child_names).uniq
  end

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def step_count
    last_user_msg = messages.where(role: "user", visible: true).order(:id).last
    return 0 unless last_user_msg
    messages.assistant.since_id(last_user_msg.id).count
  end

  # Token and cost calculation methods
  def total_input_tokens
    messages.sum(:input_tokens) || 0
  end

  def total_output_tokens
    messages.sum(:output_tokens) || 0
  end

  def total_cached_tokens
    messages.sum(:cached_tokens) || 0
  end

  def total_cache_creation_tokens
    messages.sum(:cache_creation_tokens) || 0
  end

  def total_thinking_tokens
    messages.sum(:thinking_tokens) || 0
  end

  def total_tokens
    total_input_tokens + total_output_tokens + total_thinking_tokens
  end

  def estimated_cost_usd
    return 0.0 unless model&.pricing&.dig("data", "text_tokens", "standard", "values")

    pricing = model.pricing["data"]["text_tokens"]["standard"]["values"]
    input_cost_per_million = pricing["input_per_million"] || 0
    output_cost_per_million = pricing["output_per_million"] || 0
    cached_input_cost_per_million = pricing["cached_input_per_million"] || 0

    # Calculate costs in USD
    input_cost = (total_input_tokens.to_f / 1_000_000) * input_cost_per_million
    output_cost = (total_output_tokens.to_f / 1_000_000) * output_cost_per_million
    cached_cost = (total_cached_tokens.to_f / 1_000_000) * cached_input_cost_per_million
    thinking_cost = (total_thinking_tokens.to_f / 1_000_000) * input_cost_per_million # Thinking tokens priced as input
    cache_creation_cost = (total_cache_creation_tokens.to_f / 1_000_000) * input_cost_per_million

    input_cost + output_cost + cached_cost + thinking_cost + cache_creation_cost
  end

  def formatted_cost
    cost = estimated_cost_usd
    if cost >= 1.0
      "$%.2f" % cost
    elsif cost >= 0.01
      "$%.3f" % cost
    else
      "$%.4f" % cost
    end
  end

  def total_cost_usd
    estimated_cost_usd + sub_chats.sum(&:total_cost_usd)
  end

  def formatted_total_cost
    cost = total_cost_usd
    if cost >= 1.0
      "$%.2f" % cost
    elsif cost >= 0.01
      "$%.3f" % cost
    else
      "$%.4f" % cost
    end
  end

  def total_tokens_including_sub_chats
    total_tokens + sub_chats.sum(&:total_tokens_including_sub_chats)
  end

  # Called explicitly by ConversationRunner after each AASM transition — not a callback.
  # See CLAUDE.md: broadcasts that render components belong in the caller.
  def broadcast_agent_status
    broadcast_replace_to(
      "agents",
      target: "agent_#{agent_name}",
      renderable: AgentItemComponent.new(agent: agent)
    )
  end

  def broadcast_chat_cost
    if sub_chats.any?
      broadcast_replace_to("chat_#{id}", target: "chat_#{id}_cost_totals",
        partial: "chats/cost_totals", locals: { chat: self })
      broadcast_replace_to("chat_#{id}", target: "chat_#{id}_cost_rows",
        partial: "chats/cost_rows", locals: { chat: self })
    else
      broadcast_replace_to("chat_#{id}", target: "chat_cost_#{id}",
        renderable: ChatCostComponent.new(chat: self))
    end
    parent_chat&.broadcast_chat_cost
  end

  def broadcast_chat_cost_initial
    broadcast_replace_to("chat_#{id}", target: "chat_cost_#{id}",
      renderable: ChatCostComponent.new(chat: self))
  end

  private

  # RubyLLM calls this private hook (defined in RubyLLM::ActiveRecord::ChatMethods,
  # chat_methods.rb) before every API call. We reject archived originals, then sort
  # summaries first — summaries are created after the messages they replace, so their
  # id/created_at is later, but they must appear first in the LLM context.
  def order_messages_for_llm(messages)
    active = messages.reject { |m| m.compacted_message_id.present? }
    summaries, regular = active.partition(&:summary?)
    super(summaries + regular)
  end
end
