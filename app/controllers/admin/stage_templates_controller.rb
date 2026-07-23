class Admin::StageTemplatesController < ApplicationController
  before_action :set_project_type
  before_action :set_stage_template, only: [:edit, :update, :destroy]

  def new
    @stage_template = @project_type.stage_templates.new
  end

  def create
    @stage_template = @project_type.stage_templates.new(stage_template_params)
    if @stage_template.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @stage_template.update(stage_template_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @stage_template.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.stage_templates.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_stage_template
    @stage_template = @project_type.stage_templates.find(params[:id])
  end

  def stage_template_params
    params.require(:stage_template).permit(:name, :position, :color, :default_in_filter)
  end
end
