# test/system/event_date_range_warning_test.rb
require "application_system_test_case"

class EventDateRangeWarningTest < ApplicationSystemTestCase
  test "the add-event modal warns, without blocking, when the date falls outside the chosen stage's range" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10))

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)
    click_button "Evento"

    within "#add-event-modal" do
      select stage.name, from: "Etapa"
      fill_in "Fecha", with: "06/20/2026"
      assert_selector "[data-event-date-range-warning-target='warning']:not([hidden])"
      assert_text "fuera del rango"

      find_field("Fecha").set("")
      fill_in "Fecha", with: "06/05/2026"
      assert_selector "[data-event-date-range-warning-target='warning'][hidden]", visible: :all
    end
  end

  test "the add-event modal shows no warning when 'Todo el proyecto' is selected" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.first.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10))

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)
    click_button "Evento"

    within "#add-event-modal" do
      select "Todo el proyecto", from: "Etapa"
      fill_in "Fecha", with: "06/20/2026"
      assert_selector "[data-event-date-range-warning-target='warning'][hidden]", visible: :all
    end
  end
end
