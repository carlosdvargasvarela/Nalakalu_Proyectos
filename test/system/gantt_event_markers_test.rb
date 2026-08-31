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

  test "the Gantt shows a colored marker on the 'Eventos del proyecto' row for a project-wide event" do
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

    assert_selector ".bar-wrapper[data-id='project-events']", visible: :all
    assert_selector ".event-marker", visible: :all
    fill_color = evaluate_script("document.querySelector('.event-marker').getAttribute('fill')")
    assert_equal "#00aaff", fill_color
  end

  test "the Gantt groups two same-stage events that fall within 16px into one cluster marker" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    first = Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current + 5.days, project_stage: stage)
    second = Event.create!(project: project, event_type: event_type, title: "Revisión", event_date: Date.current + 5.days, project_stage: stage)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker-group", count: 1, visible: :all
    # ponytail: dropped a contradictory assert_no_selector(".event-marker-group .event-marker[fill]") from
    # the brief - it can never pass alongside the getAttribute("fill") check below, since the cluster
    # marker's gray fill is necessarily set as an SVG attribute. The getAttribute assertion already proves
    # the marker isn't colored per-event.
    group_fill = evaluate_script("document.querySelector('.event-marker-group .event-marker').getAttribute('fill')")
    assert_equal "#495057", group_fill

    find(".event-marker-group", visible: :all).click
    assert_selector ".list-group-item", text: "Kickoff", visible: :all
    assert_selector ".list-group-item", text: "Revisión", visible: :all

    click_on "Kickoff"
    assert_selector "#edit-event-modal-#{first.id}.show", visible: :all
  end

  test "the Gantt still draws a single plain marker when only one event is at a position" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current + 5.days, project_stage: stage)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker", count: 1, visible: :all
    assert_no_selector ".event-marker-group", visible: :all
  end
end
