require "test_helper"

class Admin::DurationProfilesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }
  setup { @project_type = project_types(:instalaciones) }

  test "create adds a duration profile with per-stage durations" do
    entrega = stage_templates(:entrega)
    assert_difference("@project_type.duration_profiles.count", 1) do
      post admin_project_type_duration_profiles_path(@project_type), params: {
        duration_profile: { operator: "greater_than", min_value: 100, durations: { entrega.id.to_s => "5" } }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal 5, @project_type.duration_profiles.last.durations[entrega.id.to_s].to_i
  end

  test "create saves a profile that omits a stage's duration, like the real form submits" do
    diseno = stage_templates(:diseno_aprobacion)
    revision = stage_templates(:revision_inicial)
    produccion = stage_templates(:produccion)
    entrega = stage_templates(:entrega)
    instalacion = stage_templates(:instalacion)

    assert_difference("@project_type.duration_profiles.count", 1) do
      post admin_project_type_duration_profiles_path(@project_type), params: {
        duration_profile: {
          operator: "greater_than",
          min_value: "100",
          max_value: "",
          position: "0",
          durations: {
            diseno.id.to_s => "3",
            revision.id.to_s => "",
            produccion.id.to_s => "5",
            entrega.id.to_s => "2",
            instalacion.id.to_s => "10"
          }
        }
      }
    end
    assert_redirected_to admin_project_type_path(@project_type)

    profile = @project_type.duration_profiles.last
    assert_equal "3", profile.durations[diseno.id.to_s]
    assert_not profile.durations.key?(revision.id.to_s)
    assert_equal "5", profile.durations[produccion.id.to_s]
  end

  test "create with invalid operator re-renders form with error" do
    assert_no_difference("@project_type.duration_profiles.count") do
      post admin_project_type_duration_profiles_path(@project_type), params: {
        duration_profile: { operator: "weird" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update saves changed values" do
    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    patch admin_project_type_duration_profile_path(@project_type, profile), params: {
      duration_profile: { operator: "greater_than", min_value: 200 }
    }
    assert_redirected_to admin_project_type_path(@project_type)
    assert_equal 200, profile.reload.min_value.to_i
  end

  test "destroy removes a duration profile" do
    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    assert_difference("@project_type.duration_profiles.count", -1) do
      delete admin_project_type_duration_profile_path(@project_type, profile)
    end
  end

  test "reorder updates position according to the submitted id order" do
    first = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, position: 0)
    second = DurationProfile.create!(project_type: @project_type, operator: "less_than", max_value: 1, position: 1)

    patch reorder_admin_project_type_duration_profiles_path(@project_type), params: { ids: [second.id, first.id] }, as: :json
    assert_response :success

    assert_equal 0, second.reload.position
    assert_equal 1, first.reload.position
  end

  test "new form renders one duration input per stage template" do
    get new_admin_project_type_duration_profile_path(@project_type)
    assert_response :success
    @project_type.stage_templates.each do |stage|
      assert_select "input[name=?]", "duration_profile[durations][#{stage.id}]"
    end
  end

  test "new and edit show the submit button in Spanish" do
    get new_admin_project_type_duration_profile_path(@project_type)
    assert_response :success
    assert_select "input[value=?]", "Crear Perfil de duración"

    profile = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 100)
    get edit_admin_project_type_duration_profile_path(@project_type, profile)
    assert_response :success
    assert_select "input[value=?]", "Actualizar Perfil de duración"
  end
end
