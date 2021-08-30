class Token < Struct.new(:secret)
	# class to handle JWT token generation, to be called whenever a user signs in or a token expires
	# requires shared secret to properly sign token
	# can also check tokens it see if they've expired

	TOKEN_TIMEOUT = 4.hours

	def initialize(secret)
		self.secret = secret.to_s
	end

	def to_jwt
		payload = {iss: 'org.broadinstitute.kdux', user: 'hesc', :'org.broadinstitute.kdux.auth.roles' => ['data_reader'], exp: (Time.now + TOKEN_TIMEOUT).to_i}
		JWT.encode payload, self.secret.to_s, 'HS256'
	end

	# method to return number of milliseconds token will expire in
	# if token is expired, will return 1
	def self.expires_in(token, secret)
		now = Time.now.to_i
		begin
			data = JWT.decode token, secret, true, { :algorithm => 'HS256' }
			time = data.first['exp'] - now
			if time < 0
				1
			else
				time * 1000
			end
		rescue JWT::ExpiredSignature
			1
		end
	end

	# check to see if token has expired
	# calling !(decode token).any? will return false if the decode method returns anything other than an error
	def self.expired?(token, secret)
		begin
			!(JWT.decode token, secret, true, { :algorithm => 'HS256' }).any?
		rescue JWT::ExpiredSignature, JWT::VerificationError
			true
		end
	end
end