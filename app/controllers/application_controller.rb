class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :redirect_to_canonical_host
  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_paper_trail_whodunnit

  private

  def require_admin_or_gerente!
    return if current_user.admin? || current_user.gerente?
    redirect_to root_path, alert: "No tenés permiso para hacer eso."
  end

  # Sends anyone hitting the app on a non-canonical host (e.g. the Heroku
  # *.herokuapp.com URL) to the real domain instead, once CANONICAL_HOST is
  # set - no-op otherwise, so this is safe to ship before the domain/DNS/SSL
  # are actually ready. /up (Heroku's health check) is routed straight to
  # Rails's own Rails::HealthController, which never runs ApplicationController
  # before_actions, so it's unaffected without needing an explicit exclusion here.
  def redirect_to_canonical_host
    return unless Rails.env.production?
    canonical_host = ENV["CANONICAL_HOST"]
    return if canonical_host.blank? || request.host == canonical_host
    redirect_to "https://#{canonical_host}#{request.fullpath}", status: :moved_permanently, allow_other_host: true
  end
end
