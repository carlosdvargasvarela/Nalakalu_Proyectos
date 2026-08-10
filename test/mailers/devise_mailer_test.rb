require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  setup { @user = users(:juan) }

  test "confirmation_instructions renders the branded layout" do
    mail = Devise::Mailer.confirmation_instructions(@user, "faketoken")
    body = mail.html_part&.body&.to_s || mail.body.to_s
    assert_match "Nalakalu", body
  end
end
