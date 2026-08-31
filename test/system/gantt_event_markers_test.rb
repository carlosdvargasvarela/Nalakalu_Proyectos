require "application_system_test_case"

class GanttEventMarkersTest < ApplicationSystemTestCase
  test "the Gantt shows a colored marker over a stage for a stage-linked event" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    event_type.update!(color: "#ff00aa")
    event = Event.create!(
      project: project, event_type: event_type, title: "Kickoff",
      event_date: Date.current + 5.days, project_stage: stage
    )

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker", visible: :all
    fill_color = evaluate_script("document.querySelector('.event-marker').getAttribute('fill')")
    assert_equal "#ff00aa", fill_color

    assert_selector "#edit-event-modal-#{event.id}", visible: :all
  end

  test "the Gantt shows a native milestone bar for a project-wide event, colored by its type" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    event_type = event_types(:entrega_final)
    event_type.update!(color: "#00aaff")
    Event.create!(project: project, event_type: event_type, title: "Entrega", event_date: Date.current)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    bar_selector = ".bar-wrapper.event-color-#{event_type.id}"
    assert_selector bar_selector, visible: :all
    inline_style = evaluate_script("document.querySelector(#{bar_selector.to_json}).getAttribute('style')")
    assert_match "--bar-fill: #00aaff", inline_style
  end
end
