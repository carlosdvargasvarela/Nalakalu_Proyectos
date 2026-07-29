class ProjectAssociationsController < ApplicationController
  before_action :set_project
  before_action :authorize_edit!

  def create
    association = ProjectTypeAssociation.find(params[:project_association][:project_type_association_id])
    other_id = params[:project_association][:other_project_id]

    pa = if @project.project_type_id == association.from_project_type_id
      ProjectAssociation.new(from_project: @project, to_project_id: other_id, project_type_association: association)
    else
      ProjectAssociation.new(from_project_id: other_id, to_project: @project, project_type_association: association)
    end

    if pa.save
      redirect_to project_path(@project)
    else
      redirect_to project_path(@project), alert: pa.errors.full_messages.to_sentence
    end
  end

  def destroy
    pa = ProjectAssociation.find(params[:id])
    pa.destroy if pa.from_project_id == @project.id || pa.to_project_id == @project.id
    redirect_to project_path(@project)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end
end
