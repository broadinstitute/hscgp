require "open3"

class UserWhitelist
	include Mongoid::Document

	field :login, type: String
	field :email, type: String

	WHITELIST_FIELDS = ['user name', 'login', 'authority', 'role', 'email', 'phone', 'status', 'phsid', 'permission set',
											'created', 'updated', 'expires', 'downloader for']

	validates_uniqueness_of :email
	validates_format_of :email, with: Devise.email_regexp

	# method to decrypt downloaded dbGaP user whitelist and populate table
	# also removes any non-whitelisted users from user table
	def self.populate_whitelist(whitelist_file, encryption_key)
		Rails.logger.info "#{Time.now}: updating user whitelist using #{whitelist_file}"
		# first check if file exists
		filepath = Rails.root.join('tmp', 'whitelists', whitelist_file)
		if File.exists?(filepath)
			start_time = Time.now
			@file_data = ""

			# decrypt data from file, do test read to make sure it's ok
			begin
				i = 0
				Rails.logger.info "#{Time.now}: Decrypting #{whitelist_file}"
				# use Open3 to execute command line as this will block further execution
				Open3.popen3("mcrypt -d -a enigma -o scrypt -b -k #{encryption_key} < #{filepath}") do |stdin, stdout, stderr, thread|
					@file_data = stdout.read
				end

				# sanity check in case for some reason we exited the above block without getting data
				until !@file_data.empty? || i == 30
					sleep 1
					i += 1
				end
				# bad parsing throws ArgumentError due to invalid UTF-8 chars, calling strip will surface this error
				@file_data.split("\n").map(&:strip)
			rescue ArgumentError => e
				Rails.logger.error e.message
				Rails.logger.error "#{Time.now}: Decryption failed on #{whitelist_file}; Exiting without action"
				return
			end

			# read decrypted file, but check first in case it's empty
			whitelist_data = @file_data.split("\n").map(&:strip)
			headers = whitelist_data.shift
			unless whitelist_data.empty?
				# we have a good file, so empty whitelist collection and repopulate from file
				Rails.logger.info "#{Time.now}: User whitelist validated, removing existing whitelist pending update"
				self.destroy_all
				@whitelist_emails = []
				# now parse existing data
				whitelist_data.each do |line|
					whitelist_fields = line.split(/[\t,]/).map(&:strip)
					whitelist_email = whitelist_fields[headers.index('email')]
					whitelist_login = whitelist_fields[headers.index('login')]
					@whitelist_emails << {email: whitelist_email, login: whitelist_login}
				end
			else
				Rails.logger.error "#{Time.now}: Empty whitelist file found; Exiting without action"
				return
			end

			Rails.logger.info "#{Time.now}: Populating new user whitelist from #{whitelist_file}"
			# mass create new whitelist
			self.create(@whitelist_emails)
			new_whitelist = self.count
			# now check user table for non-whitelisted users and remove
			deleted_users = User.not_in(email: self.pluck(:email)).destroy_all

			# clean up - remove downloaded file so there is no security issue
			File.delete(filepath)

			# print messages
			end_time = Time.now
			time = (end_time - start_time).divmod 60.0
			Rails.logger.info "#{Time.now}: Finished!"
			Rails.logger.info "#{Time.now}: Total Time: #{time.first} minutes, #{time.last} seconds"
			Rails.logger.info "#{Time.now}: New whitelist: #{new_whitelist} users"
			Rails.logger.info "#{Time.now}: Removed #{deleted_users} users from user table"
			true
		else
			Rails.logger.error "#{Time.now}: Cannot open file: #{filepath}, exiting"
			false
		end
	end
end