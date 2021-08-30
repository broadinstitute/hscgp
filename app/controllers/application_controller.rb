class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception
  RECAPTCHA_MINIMUM_SCORE = 0.5

  def authenticate_admin
    unless current_user.admin?
      respond_to do |format|
        format.html { redirect_to site_path, alert: 'You do not have permission to perform that action' and return }
        format.js { head 403 }
        format.json { head 403 }
      end
    end
  end

  def verify_recaptcha?(token, recaptcha_action)
    secret_key = Rails.application.credentials.dig(:recaptcha_secret_key)

    uri = URI.parse("https://www.google.com/recaptcha/api/siteverify?secret=#{secret_key}&response=#{token}")
    response = Net::HTTP.get_response(uri)
    json = JSON.parse(response.body)
    json['success'] && json['score'] > RECAPTCHA_MINIMUM_SCORE && json['action'] == recaptcha_action
  end
end

