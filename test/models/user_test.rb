require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to visor role" do
    user = User.create!(email: "nuevo@example.com", password: "password123")
    assert user.visor?
  end

  test "role accepts admin, gerente, and visor" do
    assert User.new(role: "admin").admin?
    assert User.new(role: "gerente").gerente?
    assert User.new(role: "visor").visor?
  end

  test "admin can view and edit any project" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert users(:juan).can_view_project?(project)
    assert users(:juan).can_edit_project?(project)
  end

  test "gerente can view any project but only edit those with can_edit access" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    gerente = users(:carla)
    assert gerente.can_view_project?(project)
    assert_not gerente.can_edit_project?(project)

    ProjectAccess.create!(user: gerente, project: project, can_edit: true)
    assert gerente.can_edit_project?(project)
  end

  test "visor can only view projects with an access row, and never edits" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    visor = users(:maria)
    assert_not visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)

    ProjectAccess.create!(user: visor, project: project, can_edit: true)
    assert visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)
  end

  test "visor can also view a project through their linked responsible, without any ProjectAccess" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    visor = User.create!(email: "visor-instalador@example.com", password: "password123", role: "visor")
    responsible = Responsible.create!(name: "Visor Instalador", user: visor)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones))
    ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_types(:instalador))

    assert visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)
  end

  test "visor's responsible-linked view doesn't require a project-wide assignment, a single stage is enough" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    visor = User.create!(email: "visor-etapa@example.com", password: "password123", role: "visor")
    responsible = Responsible.create!(name: "Visor Etapa", user: visor)
    ResponsibleProjectType.create!(responsible: responsible, project_type: project_types(:instalaciones))
    ProjectResponsible.create!(
      project: project, responsible: responsible, responsible_type: responsible_types(:instalador),
      project_stage: project.project_stages.first
    )

    assert visor.can_view_project?(project)
    assert_not visor.can_edit_project?(project)
    assert_equal [project.project_stages.first.id], visor.editable_project_stage_ids(project)
  end

  test "gerente with a ProjectTypeAccess can edit any project of that type, including new ones" do
    gerente = users(:carla)
    ProjectTypeAccess.create!(user: gerente, project_type: project_types(:instalaciones), can_edit: true)

    existing = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert gerente.can_edit_project?(existing)

    later = Project.create!(project_type: project_types(:instalaciones), name: "Torre Sur", custom_fields: {})
    assert gerente.can_edit_project?(later)
  end

  test "gerente without a ProjectTypeAccess or ProjectAccess cannot edit" do
    gerente = users(:carla)
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_not gerente.can_edit_project?(project)
  end

  test "role accepts responsable" do
    assert User.new(role: "responsable").responsable?
  end

  test "responsable with a project-wide assignment can view the project and edit every stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: project, responsible: responsable.responsible,
      responsible_type: responsible_types(:instalador)
    )

    assert responsable.can_view_project?(project)
    assert_not responsable.can_edit_project?(project)
    assert_equal project.project_stage_ids.sort, responsable.editable_project_stage_ids(project).sort
  end

  test "responsable assigned to a single stage can only edit that stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    responsable = users(:pedro)
    ProjectResponsible.create!(
      project: project, responsible: responsable.responsible,
      responsible_type: responsible_types(:instalador), project_stage: stage
    )

    assert responsable.can_view_project?(project)
    assert_equal [stage.id], responsable.editable_project_stage_ids(project)
  end

  test "responsable without any assignment cannot view the project and has nothing editable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)

    assert_not responsable.can_view_project?(project)
    assert_equal [], responsable.editable_project_stage_ids(project)
  end

  test "responsable role with no linked Responsible record sees and can edit nothing" do
    unlinked = User.create!(email: "sin-vinculo@example.com", password: "password123", role: "responsable")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    assert_not unlinked.can_view_project?(project)
    assert_equal [], unlinked.editable_project_stage_ids(project)
  end

  test "admin and gerente-with-access editable_project_stage_ids covers every stage" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_equal project.project_stage_ids.sort, users(:juan).editable_project_stage_ids(project).sort

    gerente = users(:carla)
    ProjectAccess.create!(user: gerente, project: project, can_edit: true)
    assert_equal project.project_stage_ids.sort, gerente.editable_project_stage_ids(project).sort
  end

  test "gerente without edit access has nothing editable" do
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    assert_equal [], users(:carla).editable_project_stage_ids(project)
  end

  test "can_create_associated_project? is always true for admin and gerente" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})

    assert users(:juan).can_create_associated_project?(association, project)
    assert users(:carla).can_create_associated_project?(association, project)
  end

  test "can_create_associated_project? is true for an assigned responsable only when the association allows it" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    responsable = users(:pedro)
    ProjectResponsible.create!(project: project, responsible: responsable.responsible, responsible_type: responsible_types(:instalador))

    allowed = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)
    assert responsable.can_create_associated_project?(allowed, project)

    not_allowed = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Fase de", responsables_can_create: false)
    assert_not responsable.can_create_associated_project?(not_allowed, project)
  end

  test "can_create_associated_project? is false for a responsable not assigned to the target project" do
    other_type = ProjectType.create!(name: "Caso de Servicio", slug: "caso-de-servicio")
    project = Project.create!(project_type: project_types(:instalaciones), name: "Torre Norte", custom_fields: {})
    association = ProjectTypeAssociation.create!(from_project_type: other_type, to_project_type: project_types(:instalaciones), label: "Caso de servicio", responsables_can_create: true)

    assert_not users(:pedro).can_create_associated_project?(association, project)
  end
end
