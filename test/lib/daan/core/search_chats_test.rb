require "test_helper"

class Daan::Core::SearchChatsTest < ActiveSupport::TestCase
  setup do
    Daan::Core::AgentRegistry.register(build_agent(name: "developer"))
    Daan::Core::AgentRegistry.register(
      build_agent(name: "chief_of_staff", delegates_to: [ "developer" ])
    )

    @dev_chat = Chat.create!(agent_name: "developer")
    @dev_chat.messages.create!(role: "user", content: "Please implement authentication for the login page")
    @dev_chat.messages.create!(role: "assistant", content: "I will implement authentication using JWT tokens")

    @cos_chat = Chat.create!(agent_name: "chief_of_staff")
    @cos_chat.messages.create!(role: "user", content: "Set up the deployment pipeline for staging")
    @cos_chat.messages.create!(role: "assistant", content: "I will configure the deployment pipeline with CI/CD")

    @delegation_chat = Chat.create!(agent_name: "developer", parent_chat: @cos_chat)
    @delegation_chat.messages.create!(role: "user", content: "Run the database migration for authentication")
    @delegation_chat.messages.create!(role: "assistant", content: "Database migration completed successfully for authentication")

    @tool = Daan::Core::SearchChats.new
  end

  test "free-text search matches user messages" do
    result = @tool.execute(query: "authentication")

    assert_includes result, "authentication"
    assert_includes result, "developer"
  end

  test "free-text search matches assistant messages" do
    result = @tool.execute(query: "JWT")

    assert_includes result, "JWT"
    assert_includes result, "developer"
  end

  test "no results returns a no results message" do
    result = @tool.execute(query: "nonexistent_xyzzy_term")

    assert_includes result, "No results"
    assert_includes result, "nonexistent_xyzzy_term"
  end

  test "with:agent_name filters to chats owned by that agent" do
    result = @tool.execute(query: "authentication with:developer")

    assert_includes result, "developer"
    refute_includes result, "chief_of_staff"
  end

  test "with:agent_name includes chats where that agent is delegator (parent)" do
    result = @tool.execute(query: "deployment with:chief_of_staff")

    assert_includes result, "chief_of_staff"
  end

  test "with:user filters to top-level chats only" do
    result = @tool.execute(query: "authentication with:user")

    assert_includes result, @dev_chat.id.to_s
    refute_includes result, @delegation_chat.id.to_s
  end

  test "from:user filters to messages with role user" do
    result = @tool.execute(query: "authentication from:user")

    assert_includes result, "implement authentication for the login page"
    refute_includes result, ">> [assistant]"
  end

  test "from:agent_name filters to assistant messages in that agent's chats" do
    result = @tool.execute(query: "authentication from:developer")

    assert_includes result, "implement authentication using JWT"
    refute_includes result, ">> [user]"
  end

  test "before:YYYY-MM-DD date filter excludes newer messages" do
    @dev_chat.messages.where(role: "user").update_all(created_at: 2.days.ago)
    @dev_chat.messages.where(role: "assistant").update_all(created_at: 2.days.ago)
    @cos_chat.messages.update_all(created_at: 2.days.ago)
    @delegation_chat.messages.update_all(created_at: 2.days.ago)

    future_chat = Chat.create!(agent_name: "developer")
    future_chat.messages.create!(role: "user", content: "authentication future message", created_at: 1.day.from_now)

    result = @tool.execute(query: "authentication before:#{Date.today.iso8601}")

    assert_includes result, "implement authentication"
    refute_includes result, "future message"
  end

  test "after:YYYY-MM-DD date filter excludes older messages" do
    @dev_chat.messages.update_all(created_at: 5.days.ago)
    @cos_chat.messages.update_all(created_at: 5.days.ago)
    @delegation_chat.messages.update_all(created_at: 5.days.ago)

    recent_chat = Chat.create!(agent_name: "developer")
    recent_chat.messages.create!(role: "user", content: "authentication recent work")

    result = @tool.execute(query: "authentication after:#{2.days.ago.to_date.iso8601}")

    assert_includes result, "recent work"
    refute_includes result, "implement authentication for the login"
  end

  test "surrounding messages included for context" do
    result = @tool.execute(query: "JWT")

    assert_includes result, "[user]"
    assert_includes result, "[assistant]"
    assert_includes result, ">>"
  end

  test "chat metadata in results includes agent_name and chat id" do
    result = @tool.execute(query: "authentication")

    assert_includes result, "Chat ##{@dev_chat.id}"
    assert_includes result, "(developer"
    assert_includes result, "pending)"
  end

  test "handles double quotes in search terms without crashing" do
    @dev_chat.messages.create!(role: "user", content: 'Check the "authentication" module')

    result = @tool.execute(query: '"authentication"')

    assert_includes result, "authentication"
  end

  test "treats invalid date as a search term" do
    @dev_chat.messages.create!(role: "user", content: "before:not-a-date is interesting")

    result = @tool.execute(query: "before:not-a-date interesting")

    assert_includes result, "interesting"
  end

  test "returns error when query has only operators and no free text" do
    result = @tool.execute(query: "with:developer")

    assert_includes result, "no search terms"
  end

  test "results limited to 10" do
    12.times do |i|
      chat = Chat.create!(agent_name: "developer")
      chat.messages.create!(role: "user", content: "authentication query number #{i}")
    end

    result = @tool.execute(query: "authentication")

    assert_operator result.scan("Chat #").count, :<=, 10
  end
end
