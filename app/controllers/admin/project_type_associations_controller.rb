class Admin::ProjectTypeAssociationsController < Admin::BaseController
  before_action :set_project_type_association, only: [:edit, :update, :destroy]

  def index
    @project_type_associations = ProjectTypeAssociation.all
  end

  def new
    @project_type_association = ProjectTypeAssociation.new
  end

  def create
    @project_type_association = ProjectTypeAssociation.new(project_type_association_params)
    if @project_type_association.save
      redirect_to admin_project_type_associations_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project_type_association.update(project_type_association_params)
      redirect_to admin_project_type_associations_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project_type_association.destroy
    redirect_to admin_project_type_associations_path
  end

  private

  def set_project_type_association
    @project_type_association = ProjectTypeAssociation.find(params[:id])
  end

  def project_type_association_params
    params.require(:project_type_association).permit(:from_project_type_id, :to_project_type_id, :label, :responsables_can_create)
  end
end
