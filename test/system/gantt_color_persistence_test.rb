require "application_system_test_case"

class GanttColorPersistenceTest < ApplicationSystemTestCase
  test "a Gantt bar keeps its custom color after the chart receives a wheel scroll" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    responsible = Responsible.create!(name: "Responsable Color Test", color: "#ff5733")
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_type, responsible_type: responsible_types(:instalador))
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_types(:instalador))

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_type_projects_path(project_type.slug, responsible_type_id: responsible_types(:instalador).id)

    bar_selector = ".bar-wrapper.responsible-color-#{responsible.id}"
    assert_selector bar_selector, visible: :all

    inline_style = -> { evaluate_script("document.querySelector(#{bar_selector.to_json}).getAttribute('style')") }
    assert_match "--bar-fill: #ff5733", inline_style.call

    # frappe-gantt's infinite_padding feature (disabled in our Gantt options)
    # listens for "mousewheel" on its container and, when enabled, wipes and
    # redraws every bar - which used to drop this custom property. Simulate
    # that same input to prove it's now a no-op.
    evaluate_script(<<~JS)
      document.querySelector(".gantt-container").dispatchEvent(
        new WheelEvent("mousewheel", { deltaX: 5000, bubbles: true, cancelable: true })
      )
    JS

    assert_match "--bar-fill: #ff5733", inline_style.call
  end
end
