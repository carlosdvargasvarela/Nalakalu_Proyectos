class EventsController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!
  before_action :set_event, only: [:update, :destroy]

  def create
    @event = @project.events.new(event_params)
    if @event.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @event.errors.full_messages.to_sentence
    end
  end

  def update
    if @event.update(event_params)
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @event.errors.full_messages.to_sentence
    end
  end

  def destroy
    @event.destroy
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_event
    @event = @project.events.find(params[:id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  def event_params
    params.require(:event).permit(:event_type_id, :project_stage_id, :title, :event_date, :event_time, :responsible_id, :notes, :status)
  end
end
