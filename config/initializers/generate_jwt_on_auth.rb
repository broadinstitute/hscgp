# after a user signs in, generate a valid JWT token and store in session
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
	auth.env['rack.session'][:jwt_token] = Token.new(ENV['JWT_SECRET']).to_jwt
end