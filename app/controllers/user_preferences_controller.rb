class UserPreferencesController < ApplicationController
  def update
    current_user.update(show_project_progress: params[:user][:show_project_progress] == "1")
    redirect_to edit_user_registration_path, notice: "Preferencias guardadas."
  end
end
