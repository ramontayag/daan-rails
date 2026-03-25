class ChatDocumentIconComponent < ViewComponent::Base
  def initialize(chat:, show_docs: nil)
    @chat = chat
  end

  private

  attr_reader :chat

  def documents
    @documents ||= chat.documents.to_a
  end

  def document_count
    @document_count ||= documents.size
  end

  def has_documents?
    document_count > 0
  end
end
