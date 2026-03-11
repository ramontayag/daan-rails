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

    assert File.exist?(@workspace.join("chain_test.txt"))

    cos_chat = Chat.find_by!(agent_name: "chief_of_staff", parent_chat_id: nil)
    em_chat  = Chat.find_by!(agent_name: "engineering_manager", parent_chat: cos_chat)
    dev_chat = Chat.find_by!(agent_name: "developer", parent_chat: em_chat)

    cos_task_to_em  = em_chat.messages.find_by!(role: "user")
    em_task_to_dev  = dev_chat.messages.find_by!(role: "user")

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

    # Navigate to Developer — should show the task EM gave Developer, not anything from human
    click_on "Developer"
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_text em_task_to_dev.content

    # === EM perspective ===
    select "Engineering Manager", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4

    # Navigate to Developer — same EM→Dev task
    click_on "Developer"
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_text em_task_to_dev.content

    # === Developer perspective ===
    select "Developer", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4

    # Navigate to EM — should show the Developer's own chat under EM
    click_on "Engineering Manager"
    find("[data-testid='thread-list-item'] a", match: :first).click
    assert_text em_task_to_dev.content

    # === Back to human ===
    select "Me (Human)", from: "perspective"
    assert_selector "[data-testid='agent-item']", count: 4
    click_on "Chief of Staff"
    assert_selector "[data-testid='message-input']"
  end
end
