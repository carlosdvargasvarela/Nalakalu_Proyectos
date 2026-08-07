class Admin::DurationProfilesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_duration_profile, only: [:edit, :update, :destroy]

  def new
    @duration_profile = @project_type.duration_profiles.new
  end

  def create
    @duration_profile = @project_type.duration_profiles.new(duration_profile_params)
    if @duration_profile.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @duration_profile.update(duration_profile_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @duration_profile.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  def reorder
    Array(params[:ids]).each_with_index do |id, index|
      @project_type.duration_profiles.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_duration_profile
    @duration_profile = @project_type.duration_profiles.find(params[:id])
  end

  def duration_profile_params
    permitted = params.require(:duration_profile).permit(:operator, :min_value, :max_value, :position, durations: {})
    permitted[:durations] = permitted[:durations].to_h.compact_blank if permitted[:durations]
    permitted
  end
end
