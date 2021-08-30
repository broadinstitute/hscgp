class User
  include Mongoid::Document
  include Mongoid::Timestamps

  DBGAP_DOMAINS = %w(broadinstitute.org)

  # Include default devise modules. Others available are:
  # , :lockable, :timeoutable and ::omniauthable, omniauth_providers: [:shibboleth]
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :confirmable

  validate :has_dbgap_access

  ## Database authenticatable
  field :email,              type: String, default: ""
  field :encrypted_password, type: String, default: ""

  ## Recoverable
  field :reset_password_token,   type: String
  field :reset_password_sent_at, type: Time

  ## Rememberable
  field :remember_created_at, type: Time

  ## Trackable
  field :sign_in_count,      type: Integer, default: 0
  field :current_sign_in_at, type: Time
  field :last_sign_in_at,    type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip,    type: String

  ## OmniAuth
  field :uid,       type: String
  field :provider,  type: String

  ## Confirmable
  field :confirmation_token,   type: String
  field :confirmed_at,         type: Time
  field :confirmation_sent_at, type: Time
  field :unconfirmed_email,    type: String # Only if using reconfirmable

  ## Lockable
  # field :failed_attempts, type: Integer, default: 0 # Only if lock strategy is :failed_attempts
  # field :unlock_token,    type: String # Only if unlock strategy is :email or :both
  # field :locked_at,       type: Time

  # Custom
  field :admin, type: Boolean, default: false

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0,20]
    end
  end

  def has_dbgap_access
    unless UserWhitelist.where(email: self.email).exists?
      errors.add(:base, "Currently, we can only accept new users who have requested dbGap tier 2 access for this data.  We maintain an internal list of approved parties.  Please <a href='mailto:hscgp@broadinstitute.org'>contact us</a> if your lab has access.")
    end
  end
end
