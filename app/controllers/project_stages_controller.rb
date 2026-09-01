class ProjectStagesController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!
  before_action :set_project_stage, only: [:update]

  def create
    @project_stage = @project.project_stages.new(project_stage_params)
    if @project_stage.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: @project_stage.errors.full_messages.to_sentence
    end
  end

  def update
    @project_stage.update(not_applicable_param)
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_project_stage
    @project_stage = @project.project_stages.find(params[:id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to project_path(@project), alert: "No tenés permiso para hacer eso."
  end

  def project_stage_params
    params.require(:project_stage).permit(:name, :start_date, :end_date)
  end

  def not_applicable_param
    params.require(:project_stage).permit(:not_applicable)
  end
end
