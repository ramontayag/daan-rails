class ChatDocumentPanelComponent < ViewComponent::Base
  def initialize(chat:, show_docs: nil)
    @chat = chat
    @show_docs = show_docs
  end

  private

  attr_reader :chat

  def show_docs
    return @show_docs unless @show_docs.nil?
    helpers.params[:show_docs] == "1"
  end

  def documents
    @documents ||= chat.documents.to_a
  end

  def visible?
    show_docs && documents.any?
  end
end
