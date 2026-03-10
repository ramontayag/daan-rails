require "application_system_test_case"

class PerspectiveSwitchingTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(@workspace)
  end

  teardown do
    FileUtils.rm_f(@workspace.join("chain_test.txt"))
  end

  test "full delegation chain then perspective switching UI" do
    VCR.use_cassette("delegation_chain/full_chain") do
      visit chat_agent_path("chief_of_staff")

      fill_in "message[content]",
              with: 'Write "chain test passed" to chain_test.txt and summarise it for me'
      click_button "Send"

      assert_selector "[data-testid='thread-panel']"
      assert_selector "[data-role='assistant']", minimum: 1
    end

    cos_chat = Chat.find_by(agent_name: "chief_of_staff")
    em_chat  = Chat.find_by(agent_name: "engineering_manager", parent_chat: cos_chat)

    assert File.exist?(@workspace.join("chain_test.txt"))

    # Switch to CoS perspective — sidebar shows only EM
    select "Chief of Staff", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 1
    assert_selector "[data-testid='agent-item']", text: "Engineering Manager"

    # Open the EM thread
    click_on "Engineering Manager"
    find("[data-testid='thread-list-item'] a", match: :first).click

    # Read-only compose bar
    assert_no_selector "[data-testid='message-input']"
    assert_text "read-only"

    # EM's messages right-aligned
    assert_selector ".text-right", minimum: 1

    # Hide/show tools
    click_on "Hide tools"
    assert_no_selector "[data-testid='tool-call']"
    click_on "Show tools"
    assert_selector "[data-testid='tool-call']", minimum: 1

    # EM perspective — CoS and Developer in sidebar
    select "Engineering Manager", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 2

    # Back to human — compose bar active
    select "Me (Human)", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 3
    click_on "Chief of Staff"
    assert_selector "[data-testid='message-input']"
  end
end
