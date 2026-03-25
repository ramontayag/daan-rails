class ChatDocumentIconComponent < ViewComponent::Base
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

  def document_count
    @document_count ||= chat.documents.count
  end

  def has_documents?
    document_count > 0
  end
end
