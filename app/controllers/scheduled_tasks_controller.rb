class ScheduledTasksController < ApplicationController
  before_action :set_task, only: [ :edit, :update, :destroy ]
  before_action :set_return_to_uri

  def index
    @recurring_tasks = ScheduledTask.recurring.order(created_at: :desc)
    @one_shot_tasks  = ScheduledTask.where(task_type: :one_shot).order(run_at: :asc)
  end

  def new
    @task = ScheduledTask.new
  end

  def create
    @task = ScheduledTask.new(task_params)
    if @task.save
      redirect_to scheduled_tasks_path(return_to_uri: @return_to_uri), notice: "Scheduled task created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      redirect_to scheduled_tasks_path(return_to_uri: @return_to_uri), notice: "Scheduled task updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    redirect_to scheduled_tasks_path(return_to_uri: @return_to_uri), notice: "Scheduled task deleted."
  end

  private

  def set_task
    @task = ScheduledTask.find(params[:id])
  end

  def set_return_to_uri
    @return_to_uri = safe_return_uri(params[:return_to_uri])
  end

  def task_params
    params.require(:scheduled_task).permit(
      :agent_name, :message, :schedule, :timezone, :enabled
    )
  end
end
