class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_paper_trail_whodunnit

  private

  def require_admin_or_gerente!
    return if current_user.admin? || current_user.gerente?
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end
end
