require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "redirects to CANONICAL_HOST in production when the request host differs" do
    with_env("CANONICAL_HOST" => "proyectos-nalakalu.com") do
      Rails.env.stub(:production?, true) do
        get root_url(host: "nalakalu-proyectos-8c45fab9f47c.herokuapp.com")
        assert_response :moved_permanently
        assert_redirected_to "https://proyectos-nalakalu.com/"
      end
    end
  end

  test "does not redirect when already on CANONICAL_HOST" do
    with_env("CANONICAL_HOST" => "proyectos-nalakalu.com") do
      Rails.env.stub(:production?, true) do
        get root_url(host: "proyectos-nalakalu.com")
        assert_response :success
      end
    end
  end

  test "does not redirect when CANONICAL_HOST is not set" do
    Rails.env.stub(:production?, true) do
      get root_url(host: "nalakalu-proyectos-8c45fab9f47c.herokuapp.com")
      assert_response :success
    end
  end

  test "does not redirect outside production even when CANONICAL_HOST is set" do
    with_env("CANONICAL_HOST" => "proyectos-nalakalu.com") do
      get root_url(host: "nalakalu-proyectos-8c45fab9f47c.herokuapp.com")
      assert_response :success
    end
  end

  private

  def with_env(vars)
    originals = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
