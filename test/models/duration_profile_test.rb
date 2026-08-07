require "test_helper"

class DurationProfileTest < ActiveSupport::TestCase
  setup { @project_type = project_types(:instalaciones) }

  test "valid with greater_than and min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "greater_than", min_value: 100)
    assert profile.valid?, profile.errors.full_messages.to_s
  end

  test "invalid operator" do
    profile = DurationProfile.new(project_type: @project_type, operator: "weird", min_value: 100)
    assert_not profile.valid?
  end

  test "greater_than requires min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "greater_than")
    assert_not profile.valid?
    assert_includes profile.errors[:min_value], "es obligatorio para este operador"
  end

  test "less_than requires max_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "less_than")
    assert_not profile.valid?
    assert_includes profile.errors[:max_value], "es obligatorio para este operador"
  end

  test "between requires both min_value and max_value, and min <= max" do
    profile = DurationProfile.new(project_type: @project_type, operator: "between", min_value: 500, max_value: 100)
    assert_not profile.valid?
    assert_includes profile.errors[:max_value], "debe ser mayor o igual al valor mínimo"
  end

  test "equal_to requires min_value" do
    profile = DurationProfile.new(project_type: @project_type, operator: "equal_to")
    assert_not profile.valid?
    assert_includes profile.errors[:min_value], "es obligatorio para este operador"
  end

  test "durations must reference stage_templates belonging to the same project_type" do
    other_type = ProjectType.create!(name: "Otro", slug: "otro")
    foreign_stage = StageTemplate.create!(project_type: other_type, name: "Ajena")
    profile = DurationProfile.new(
      project_type: @project_type, operator: "greater_than", min_value: 1,
      durations: { foreign_stage.id.to_s => 5 }
    )
    assert_not profile.valid?
    assert_includes profile.errors[:durations], "hace referencia a un subproceso inválido"
  end

  test "durations values must be positive integers" do
    stage = stage_templates(:entrega)
    profile = DurationProfile.new(
      project_type: @project_type, operator: "greater_than", min_value: 1,
      durations: { stage.id.to_s => -3 }
    )
    assert_not profile.valid?
    assert_includes profile.errors[:durations], "debe ser un número de días positivo"
  end

  test "matches? for greater_than" do
    profile = DurationProfile.new(operator: "greater_than", min_value: 100)
    assert profile.matches?(150)
    assert_not profile.matches?(100)
    assert_not profile.matches?(50)
  end

  test "matches? for less_than" do
    profile = DurationProfile.new(operator: "less_than", max_value: 100)
    assert profile.matches?(50)
    assert_not profile.matches?(100)
    assert_not profile.matches?(150)
  end

  test "matches? for between" do
    profile = DurationProfile.new(operator: "between", min_value: 100, max_value: 500)
    assert profile.matches?(100)
    assert profile.matches?(500)
    assert profile.matches?(300)
    assert_not profile.matches?(99)
    assert_not profile.matches?(501)
  end

  test "matches? for equal_to" do
    profile = DurationProfile.new(operator: "equal_to", min_value: 42)
    assert profile.matches?(42)
    assert_not profile.matches?(43)
  end

  test "project_type has_many duration_profiles ordered by position" do
    second = DurationProfile.create!(project_type: @project_type, operator: "greater_than", min_value: 1, position: 1)
    first = DurationProfile.create!(project_type: @project_type, operator: "less_than", max_value: 1, position: 0)
    assert_equal [first, second], @project_type.duration_profiles.to_a
  end
end
