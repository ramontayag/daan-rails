require "test_helper"

class ScheduledTasksFlowTest < ActionDispatch::IntegrationTest
  setup do
    ScheduledTask.destroy_all
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  # ---- index ----

  test "index renders a list of scheduled tasks" do
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "Digest",
                          schedule: "every day at 8am", timezone: "UTC")

    get scheduled_tasks_path
    assert_response :success
    assert_select "[data-testid='scheduled-task-row']", 1
  end

  test "index shows enabled and disabled tasks" do
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                          schedule: "every day at 8am", timezone: "UTC", enabled: true)
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "B",
                          schedule: "every day at 9am", timezone: "UTC", enabled: false)

    get scheduled_tasks_path
    assert_response :success
    assert_select "[data-testid='scheduled-task-row']", 2
  end

  # ---- new / create ----

  test "new renders the form" do
    get new_scheduled_task_path
    assert_response :success
    assert_select "form[action*='scheduled_tasks']"
  end

  test "create with valid params redirects to index" do
    assert_difference "ScheduledTask.count", 1 do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "chief_of_staff",
          message: "Daily digest",
          schedule: "every day at 8am",
          timezone: "America/New_York"
        }
      }
    end
    assert_redirected_to scheduled_tasks_path(return_to_uri: "/")
  end

  test "create with invalid schedule re-renders form" do
    assert_no_difference "ScheduledTask.count" do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "chief_of_staff",
          message: "Daily digest",
          schedule: "not a schedule",
          timezone: "UTC"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create with missing agent_name re-renders form" do
    assert_no_difference "ScheduledTask.count" do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "",
          message: "Daily digest",
          schedule: "every day at 8am",
          timezone: "UTC"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # ---- edit / update ----

  test "edit renders the form" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC")
    get edit_scheduled_task_path(task)
    assert_response :success
    assert_select "form[action*='scheduled_tasks']"
  end

  test "update with valid params redirects to index" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "Old",
                                 schedule: "every day at 8am", timezone: "UTC")
    patch scheduled_task_path(task), params: {
      scheduled_task: { message: "New message", timezone: "America/Chicago" }
    }
    assert_redirected_to scheduled_tasks_path(return_to_uri: "/")
    assert_equal "New message", task.reload.message
    assert_equal "America/Chicago", task.reload.timezone
  end

  test "update with invalid schedule re-renders form" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "Old",
                                 schedule: "every day at 8am", timezone: "UTC")
    patch scheduled_task_path(task), params: {
      scheduled_task: { schedule: "garbage" }
    }
    assert_response :unprocessable_entity
    assert_equal "every day at 8am", task.reload.schedule
  end

  # ---- destroy ----

  test "destroy deletes the record and redirects to index" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC")
    assert_difference "ScheduledTask.count", -1 do
      delete scheduled_task_path(task)
    end
    assert_redirected_to scheduled_tasks_path(return_to_uri: "/")
  end

  # ---- toggle enabled ----

  test "update can toggle enabled to false" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC", enabled: true)
    patch scheduled_task_path(task), params: {
      scheduled_task: { enabled: false }
    }
    assert_redirected_to scheduled_tasks_path(return_to_uri: "/")
    assert_not task.reload.enabled?
  end

  test "update can toggle enabled to true" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC", enabled: false)
    patch scheduled_task_path(task), params: {
      scheduled_task: { enabled: true }
    }
    assert_redirected_to scheduled_tasks_path(return_to_uri: "/")
    assert task.reload.enabled?
  end
end
