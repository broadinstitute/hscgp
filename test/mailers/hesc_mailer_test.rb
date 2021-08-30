require 'test_helper'

class HescMailerTest < ActionMailer::TestCase
  test "help_request" do
    mail = HescMailer.help_request
    assert_equal "Help request", mail.subject
    assert_equal ["to@example.org"], mail.to
    assert_equal ["from@example.com"], mail.from
    assert_match "Hi", mail.body.encoded
  end

end
