class Admin::FieldDefinitionsController < ApplicationController
  before_action :set_project_type
  before_action :set_field_definition, only: [:edit, :update, :destroy]

  def new
    @field_definition = @project_type.field_definitions.new
  end

  def create
    @field_definition = @project_type.field_definitions.new(field_definition_params)
    if @field_definition.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @field_definition.update(field_definition_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @field_definition.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.field_definitions.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_field_definition
    @field_definition = @project_type.field_definitions.find(params[:id])
  end

  def field_definition_params
    params.require(:field_definition).permit(:key, :label, :data_type, :reference_table, :position, :show_in_gantt)
  end
end
