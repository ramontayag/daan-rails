class Document < ApplicationRecord
  belongs_to :chat

  validates :title, presence: true
end
