class ProjectResponsiblesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    @project_responsible = @project.project_responsibles.new(project_responsible_params)
    if @project_responsible.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_responsible.errors.full_messages.to_sentence
    end
  end

  def destroy
    @project.project_responsibles.find(params[:id]).destroy
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  def project_responsible_params
    params.require(:project_responsible).permit(:responsible_id, :responsible_type_id, :project_stage_id)
  end
end
