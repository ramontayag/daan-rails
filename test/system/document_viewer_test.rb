require "application_system_test_case"

class DocumentViewerTest < ApplicationSystemTestCase
  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    ActiveJob::Base.queue_adapter = :test

    @chat = Chat.create!(agent_name: "chief_of_staff")
    @doc = Document.create!(
      title: "Architecture Plan",
      body: "# Architecture\n\nThis is the plan.",
      chat: @chat
    )
  end

  test "clicking a document title opens the show page and X returns to thread" do
    visit chat_thread_path(@chat)

    # Icon appears with count badge
    find("[data-controller='popover']").click

    # Dropdown opens showing the document title as a link
    within "[data-popover-target='panel']" do
      click_link "Architecture Plan"
    end

    # Full-screen document page
    assert_current_path document_path(@doc), ignore_query: true
    assert_selector "h1", text: "Architecture Plan"
    assert_text "This is the plan."

    # X button returns to the thread
    find("[title='Close']").click
    assert_current_path chat_thread_path(@chat)
  end
end
