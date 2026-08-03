class Admin::ProjectTypeAssociationsController < Admin::BaseController
  before_action :set_project_type_association, only: [:edit, :update, :destroy]
  before_action :set_field_definitions_by_type, only: [:new, :create, :edit, :update]

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

  def set_field_definitions_by_type
    @field_definitions_by_type = ProjectType.includes(:field_definitions).each_with_object({}) do |project_type, hash|
      hash[project_type.id] = [{ key: "name", label: "Nombre", data_type: "text", reference_table: nil }] + project_type.field_definitions.map do |field|
        { key: field.key, label: field.label, data_type: field.data_type, reference_table: field.reference_table }
      end
    end
  end

  def project_type_association_params
    permitted = params.require(:project_type_association).permit(
      :from_project_type_id, :to_project_type_id, :label, :responsables_can_create,
      shared_field_mappings: [:from, :to]
    )
    if permitted.key?(:shared_field_mappings)
      permitted[:shared_field_mappings] = permitted[:shared_field_mappings].reject { |m| m[:from].blank? || m[:to].blank? }
    end
    permitted
  end
end
