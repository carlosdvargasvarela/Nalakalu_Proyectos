class Admin::ResponsiblesController < Admin::BaseController
  before_action :set_responsible, only: [:edit, :update, :destroy]

  def index
    @responsibles = Responsible.all
  end

  def new
    @responsible = Responsible.new
  end

  def create
    @responsible = Responsible.new(responsible_params)
    if @responsible.save
      redirect_to admin_responsibles_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @responsible.update(responsible_params)
      redirect_to admin_responsibles_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible.destroy
    redirect_to admin_responsibles_path
  end

  private

  def set_responsible
    @responsible = Responsible.find(params[:id])
  end

  def unlinked_users
    User.where.missing(:responsible).or(User.where(id: @responsible&.user_id))
  end
  helper_method :unlinked_users

  def responsible_params
    params.require(:responsible).permit(:name, :color, :user_id)
  end
end
