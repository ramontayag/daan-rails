require "application_system_test_case"

class PerspectiveSwitchingTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @em_workspace = Rails.root.join("tmp", "workspaces", "engineering_manager")
    FileUtils.mkdir_p(@em_workspace)
  end

  teardown do
    FileUtils.rm_f(@em_workspace.join("chain_test.txt"))
  end

  test "human sends message, chain completes, perspective switching shows correct conversations" do
    VCR.use_cassette("delegation_chain/full_chain") do
      visit root_path
      click_on "Chief of Staff"

      fill_in "message[content]",
              with: 'Write "chain test passed" to chain_test.txt and summarise it for me'
      click_button "Send"

      assert_selector "[data-testid='thread-panel']"
      assert_selector "[data-role='assistant']", minimum: 1
    end

    assert File.exist?(@em_workspace.join("chain_test.txt"))

    cos_chat = Chat.find_by!(agent_name: "chief_of_staff", parent_chat_id: nil)
    em_chat  = Chat.find_by!(agent_name: "engineering_manager", parent_chat: cos_chat)

    cos_task_to_em = em_chat.messages.find_by!(role: "user")

    # === CoS perspective ===
    select "Chief of Staff", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4

    # CoS's own page — shows conversation with the human
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_selector "[data-role='user']"
    assert_no_selector "[data-testid='message-input']"
    assert_text "read-only"

    # Navigate to EM — should show the task CoS gave EM, not anything from human
    click_on "Engineering Manager"
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_text cos_task_to_em.content

    # === EM perspective ===
    select "Engineering Manager", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4

    # EM can see its own conversation with CoS
    click_on "Chief of Staff"
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_text cos_task_to_em.content

    # === Back to human ===
    select "Me (Human)", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4
    click_on "Chief of Staff"
    assert_selector "[data-testid='message-input']"
  end
end
