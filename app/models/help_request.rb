class HelpRequest
	include ActiveModel::Model
	attr_accessor :email, :subject, :content, :attachment

	#include SimpleCaptcha::ModelHelpers
	#apply_simple_captcha :message => "code did not match secret image"

	validates :email, presence: true, format: { with: Devise.email_regexp }
	validates_presence_of :subject, :content
end
