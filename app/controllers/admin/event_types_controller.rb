class Admin::EventTypesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_event_type, only: [:edit, :update, :destroy]

  def new
    @event_type = @project_type.event_types.new
  end

  def create
    @event_type = @project_type.event_types.new(event_type_params)
    if @event_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event_type.update(event_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @event_type.destroy
      redirect_to admin_project_type_path(@project_type)
    else
      redirect_to admin_project_type_path(@project_type), alert: @event_type.errors.full_messages.to_sentence
    end
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.event_types.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_event_type
    @event_type = @project_type.event_types.find(params[:id])
  end

  def event_type_params
    params.require(:event_type).permit(:name, :position, :color, :icon)
  end
end
