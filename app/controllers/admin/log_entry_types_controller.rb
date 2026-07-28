class Admin::LogEntryTypesController < ApplicationController
  before_action :set_project_type
  before_action :set_log_entry_type, only: [:edit, :update, :destroy]

  def new
    @log_entry_type = @project_type.log_entry_types.new
  end

  def create
    @log_entry_type = @project_type.log_entry_types.new(log_entry_type_params)
    if @log_entry_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @log_entry_type.update(log_entry_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @log_entry_type.destroy
      redirect_to admin_project_type_path(@project_type)
    else
      redirect_to admin_project_type_path(@project_type), alert: @log_entry_type.errors.full_messages.to_sentence
    end
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_log_entry_type
    @log_entry_type = @project_type.log_entry_types.find(params[:id])
  end

  def log_entry_type_params
    params.require(:log_entry_type).permit(:name, :color)
  end
end
