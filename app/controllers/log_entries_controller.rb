class LogEntriesController < ApplicationController
  before_action :set_project

  def create
    @log_entry = @project.log_entries.new(log_entry_params.merge(user: current_user))
    if @log_entry.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @log_entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    log_entry = @project.log_entries.find(params[:id])
    log_entry.destroy if log_entry.user == current_user
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def log_entry_params
    params.require(:log_entry).permit(:body, :log_entry_type_id)
  end
end
