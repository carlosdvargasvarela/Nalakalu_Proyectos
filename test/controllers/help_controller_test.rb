require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:juan) }

  test "show renders a known topic's markdown as HTML" do
    get help_topic_path(topic: "projects")
    assert_response :success
    assert_match "<h2>", @response.body
    assert_match "Proyectos", @response.body
  end

  test "show 404s for an unknown topic" do
    get help_topic_path(topic: "no-existe")
    assert_response :not_found
  end

  test "show 404s on path traversal instead of leaking files outside docs/help" do
    get "/help/..%2F..%2F..%2F..%2F..%2Fetc%2Fpasswd"
    assert_response :not_found
  end

  test "show 404s when the topic path helper is given a traversal attempt" do
    get help_topic_path(topic: "../../Gemfile")
    assert_response :not_found
  end

  test "show 404s instead of raising on a topic containing a null byte" do
    get "/help/foo%00bar"
    assert_response :not_found
  end

  test "show renders a nested admin topic" do
    get help_topic_path(topic: "admin/project_types")
    assert_response :success
    assert_match "Tipos de proyecto", @response.body
  end
end
