require "application_system_test_case"

class DocumentMessageLinkTest < ApplicationSystemTestCase
  setup do
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    ActiveJob::Base.queue_adapter = :test

    @chat = Chat.create!(agent_name: "chief_of_staff")
    @doc = Document.create!(title: "Architecture Plan", body: "# Plan", chat: @chat)
    @chat.messages.create!(
      role: "assistant",
      content: "I've created [Architecture Plan](/documents/#{@doc.id}) for you."
    )
  end

  test "document link in message opens show page and X returns to thread" do
    visit chat_thread_path(@chat)

    click_link "Architecture Plan"

    assert_current_path document_path(@doc), ignore_query: true
    assert_selector "h1", text: "Architecture Plan"

    find("[title='Close']").click

    assert_current_path chat_thread_path(@chat)
  end
end
