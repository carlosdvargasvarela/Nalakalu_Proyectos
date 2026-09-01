class LogEntriesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!, only: [:create, :destroy]
  before_action :set_log_entry, only: [:update, :destroy]

  def create
    @log_entry = @project.log_entries.new(log_entry_params.merge(user: current_user))
    if @log_entry.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @log_entry.errors.full_messages.to_sentence
    end
  end

  def update
    return redirect_to(project_path(@project), alert: "No tenés permiso para modificar esta nota.") unless can_modify_entry?

    if @log_entry.update(log_entry_params)
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @log_entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    @log_entry.destroy if @log_entry.user == current_user
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_log_entry
    @log_entry = @project.log_entries.find(params[:id])
  end

  # Anyone with admin/gerente rank can fix any note; otherwise only the
  # author can edit theirs, and only while they still have access to add
  # notes to this project (mirrors destroy's re-check on revoked access).
  def can_modify_entry?
    return true if current_user.admin? || current_user.gerente?
    return false unless @log_entry.user == current_user
    current_user.can_edit_project?(@project) || (current_user.visor? && current_user.can_view_project?(@project))
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    return if current_user.visor? && current_user.can_view_project?(@project)
    redirect_to project_path(@project), alert: "No tenés permiso para agregar notas a este proyecto."
  end

  def log_entry_params
    params.require(:log_entry).permit(:body, :log_entry_type_id)
  end
end
