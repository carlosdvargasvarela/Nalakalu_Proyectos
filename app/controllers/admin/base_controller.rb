class Admin::BaseController < ApplicationController
  before_action :require_admin!

  private

  def require_admin!
    return if current_user&.admin?
    redirect_to root_path, alert: "No tenés permiso para acceder a esa sección."
  end
end
