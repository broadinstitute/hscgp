# Preview all emails at http://localhost:3000/rails/mailers/hesc_mailer
class HescMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/hesc_mailer/help_request
  def help_request
    HescMailer.help_request
  end

end
