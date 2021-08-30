class HescMailer < ApplicationMailer
  # require 'sendgrid-ruby'

  default to: Rails.env == 'hscgportalhelp@gmail.com'


  def help_request(help_request)
    @help_request = help_request
    file = @help_request.attachment
    if file.present?
      attachments[file.original_filename] = {mime_type: file.content_type,
                                           content: File.read(file.tempfile)}
    end
    mail(from: @help_request.email, subject: @help_request.subject)
  end
end
