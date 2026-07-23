class ProjectStagesController < ApplicationController
  before_action :set_project
  before_action :set_project_stage

  def edit
  end

  def update
    if @project_stage.update(project_stage_params)
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_project_stage
    @project_stage = @project.project_stages.find(params[:id])
  end

  def project_stage_params
    params.require(:project_stage).permit(:start_date, :end_date, :progress_percent, :user_id)
  end
end
