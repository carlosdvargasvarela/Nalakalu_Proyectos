class Admin::InstallersController < ApplicationController
  before_action :set_installer, only: [:edit, :update, :destroy]

  def index
    @installers = Installer.all
  end

  def new
    @installer = Installer.new
  end

  def create
    @installer = Installer.new(installer_params)
    if @installer.save
      redirect_to admin_installers_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @installer.update(installer_params)
      redirect_to admin_installers_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @installer.destroy
    redirect_to admin_installers_path
  end

  private

  def set_installer
    @installer = Installer.find(params[:id])
  end

  def installer_params
    params.require(:installer).permit(:name, :color)
  end
end
