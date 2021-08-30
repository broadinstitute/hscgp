##
# FireCloudClient: Class that wraps API calls to both api.firecloud.org and Google Cloud Storage
# 
# requirements:
# * googleauth (for generating access tokens)
# * google-cloud-storage (for bucket/file access)
# * rest-client (for HTTP calls)
#
# Author::  Jon Bistline  (mailto:bistline@broadinstitute.org)

class FireCloudClient < Struct.new(:project, :access_token, :api_root, :storage, :expires_at, :service_account_credentials)

  #
  # CONSTANTS
  #

  # base url for all API calls
  BASE_URL = 'https://api.firecloud.org'
  # default auth scopes
  GOOGLE_SCOPES = %w(https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/devstorage.read_only)
  # constant used for retry loops in process_firecloud_request and execute_gcloud_method
  MAX_RETRY_COUNT = 5
  # constant used for incremental backoffs on retries (in seconds); ignored when running unit/integration test suite
  RETRY_INTERVAL = Rails.env.test? ? 0 : 15
  # List of URLs/Method names to never retry on or report error, regardless of error state
  ERROR_IGNORE_LIST = ["#{BASE_URL}/register"]
  # List of URLs/Method names to ignore incremental backoffs on (in cases of UI blocking)
  RETRY_BACKOFF_BLACKLIST = ["#{BASE_URL}/register", :generate_signed_url, :generate_api_url]
  # default namespace used for all FireCloud workspaces owned by the 'portal'
  PORTAL_NAMESPACE = ENV['PORTAL_NAMESPACE']
  # location of Google service account JSON (must be absolute path to file)
  SERVICE_ACCOUNT_KEY = !ENV['SERVICE_ACCOUNT_KEY'].blank? ? File.absolute_path(ENV['SERVICE_ACCOUNT_KEY']) : ''
  
  ##
  # SERVICE NAMES AND DESCRIPTIONS
  #
  # The following constants are named FireCloud "services" that cover various pieces of functionality that
  # SCP depends on.  These names are stored here to reduce duplication and prevent typos.
  # A list of all available service names can be retrieved with FireCloudClient#api_status
  ##

  # Rawls is the largest service that pertains to workspaces and pipeline submissions via the managed Cromwell instance
  # SCP uses Rawls for updating studies, uploading/parsing files, launching workflows
  RAWLS_SERVICE = 'Rawls'
  # SAM holds most of the workspace permissions and other features
  # SCP uses Sam for updating studies, uploading/parsing files
  SAM_SERVICE = 'Sam'
  # Agora covers the Methods repository and other analysis-oriented features
  # SCP uses Agora for configuring new analyses, submitting workflows
  AGORA_SERVICE = 'Agora'
  # Thurloe covers Terra profiles and billing projects
  # SCP uses Thurloe for managing user's Terra profiles and billing projects
  THURLOE_SERVICE = 'Thurloe'
  # Workspaces come with GCP buckets, and the GoogleBuckets service helps manage permissions
  # SCP requires GoogleBuckets to be up for uploading/downloading files, even though SCP uses the GCS JSON API directly
  # via the google-cloud-storage gem.
  BUCKETS_SERVICE = 'GoogleBuckets'

  ##
  # METHODS
  ##

  # initialize is called after instantiating with FireCloudClient.new
  # will set the access token, FireCloud api url root and GCP storage driver instance
  #
  # * *params*
  #   - +user+: (User) => User object from which access tokens are generated
  #   - +project+: (String) => Default GCP Project to use (can be overridden by other parameters)
  # * *return*
  #   - +FireCloudClient+ object
  def initialize(project=PORTAL_NAMESPACE, service_account=SERVICE_ACCOUNT_KEY)
    # instantiate Google Cloud Storage driver to work with files in workspace buckets
    # if no keyfile is present, use environment variables
    storage_attr = {
        project: PORTAL_NAMESPACE,
        timeout: 3600
    }

    if !service_account.blank?
      storage_attr.merge!(keyfile: service_account)
      self.service_account_credentials = service_account
    end

    self.access_token = FireCloudClient.generate_access_token(service_account)
    self.project = project
    self.storage = Google::Cloud::Storage.new(storage_attr)

    # set expiration date of token
    self.expires_at = Time.zone.now + self.access_token['expires_in']
    
    # set FireCloud API base url
    self.api_root = BASE_URL
  end

  # return a hash of instance attributes for this client
  #
  # * *return*
  #   - +Hash+ of values for all instance variables for this client
  def attributes
    sanitized_values = self.to_h.dup
    sanitized_values[:access_token] = 'REDACTED'
    sanitized_values[:issuer] = self.issuer
    sanitized_values
  end

  #
  # TOKEN METHODS
  #

  # generate an access token to use for all requests
  #
  # * *return*
  #   - +Hash+ of Google Auth access token (contains access_token (string), token_type (string) and expires_in (integer, in seconds)
  def self.generate_access_token(service_account)
    # if no keyfile present, use environment variables
    creds_attr = {scope: GOOGLE_SCOPES}
    if !service_account.blank?
      creds_attr.merge!(json_key_io: File.open(service_account))
    end
    creds = Google::Auth::ServiceAccountCredentials.make_creds(creds_attr)
    token = creds.fetch_access_token!
    token
  end

  # refresh access_token when expired and stores back in FireCloudClient instance
  #
  # * *return*
  #   - +DateTime+ timestamp of new access token expiration
  def refresh_access_token
    new_token = FireCloudClient.generate_access_token(self.service_account_credentials)
    new_expiry = Time.zone.now + new_token['expires_in']
    self.access_token = new_token
    self.expires_at = new_expiry
    new_token
  end

  # check if an access_token is expired
  #
  # * *return*
  #   - +Boolean+ of token expiration
  def access_token_expired?
    Time.zone.now >= self.expires_at
  end

  # return a valid access token
  #
  # * *return*
  #   - +Hash+ of access token
  def valid_access_token
    self.access_token_expired? ? self.refresh_access_token : self.access_token
  end

  ##
  ## STORAGE INSTANCE METHODS
  ##

  # get issuer of storage credentials
  #
  # * *return*
  #   - +String+ of issuer email
  def storage_issuer
    self.storage.service.credentials.issuer
  end

  # get issuer of access_token
  #
  # * *return*
  #   - +String+ of access_token issuer email
  def issuer
    self.storage_issuer
  end

  # identify user initiating a request; either self.user, Current.user, or service account
  #
  # *return*
  #   - +String+ db identifier of user, or service account email
  def tracking_identifier
    self.issuer
  end

  ######
  ##
  ## FIRECLOUD METHODS
  ##
  ######

  # generic handler to execute http calls, process returned JSON and handle exceptions
  #
  # * *params*
  #   - +http_method+ (String, Symbol) => valid http method
  #   - +path+ (String) => FireCloud REST API path
  #   - +payload+ (Hash) => HTTP POST/PATCH/PUT body for creates/updates, defaults to nil
  #		- +opts+ (Hash) => Hash of extra options (defaults are file_upload=false, max_attemps=MAX_RETRY_COUNT)
  #   - +retry_count+ (Integer) => current count of number of retries.  defaults to 0 and self-increments
  #
  # * *return*
  #   - +Hash+, +Boolean+ depending on response body
  # * *raises*
  #   - +RestClient::Exception+
  def process_firecloud_request(http_method, path, payload=nil, opts={}, retry_count=0)
    # set up default options
    request_opts = {file_upload: false}.merge(opts)

    # Log API call for auditing/tracking purposes
    Rails.logger.info "FireCloud API request (#{http_method.to_s.upcase}) #{path} with tracking identifier: #{self.tracking_identifier}"
    # check for token expiry first before executing
    if self.access_token_expired?
      Rails.logger.info "FireCloudClient token expired, refreshing access token"
      self.refresh_access_token
    end
    # set default headers, appending application identifier including hostname for disambiguation
    headers = {
        'Authorization' => "Bearer #{self.access_token['access_token']}",
        'x-app-id' => Rails.application.class.parent.name.underscore,
        'x-domain-id' => "#{ENV['HOSTNAME']}",
        'x-user-id' => "#{self.tracking_identifier}"
    }
    # if not uploading a file, set the content_type to application/json
    if !request_opts[:file_upload]
      headers.merge!({'Content-Type' => 'application/json'})
    end

    # process request
    begin
      response = RestClient::Request.execute(method: http_method, url: path, payload: payload, headers: headers)
      #Rails.logger.info("Requesting {'method':'#{http_method}', 'url': '#{path}', 'payload': '#{payload}', 'headers': '#{headers}'")
      # handle response using helper
      handle_response(response)
    rescue RestClient::Exception => e
      current_retry = retry_count + 1
      context = " encountered when requesting '#{path}', attempt ##{current_retry}"
      log_message = "#{e.message}: #{e.http_body}; #{context}"
      Rails.logger.error log_message
      retry_time = retry_count * RETRY_INTERVAL
      sleep(retry_time) unless RETRY_BACKOFF_BLACKLIST.include?(path) # only sleep if non-blocking
      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries
      if should_retry?(e.http_code) && retry_count < MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(path)
        process_firecloud_request(http_method, path, payload, opts, current_retry)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        error_message = parse_error_message(e)
        Rails.logger.error "Retry count exceeded when requesting '#{path}' - #{error_message}"
        raise e
      end
    end
  end

  ##
  ## API STATUS
  ##

  # determine if FireCloud api is currently up/available
  #
  # * *return*
  #   - +Boolean+ indication of FireCloud current root status
  def api_available?
    begin
      response = self.api_status
      if response.is_a?(Hash) && response['ok']
        true
      else
        false
      end
    rescue => e
      false
    end
  end

  # get more detailed status information about FireCloud api
  # this method doesn't use process_firecloud_request as we want to preserve error states rather than catch and suppress them
  #
  # * *return*
  #   - +Hash+ with health status information for various FireCloud services or error response
  def api_status
    path = self.api_root + '/status'
    # make sure access token is still valid
    headers = {
        'Authorization' => "Bearer #{self.valid_access_token['access_token']}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
    }
    begin
      response = RestClient::Request.execute(method: :get, url: path, headers: headers)
      JSON.parse(response.body)
    rescue RestClient::ExceptionWithResponse => e
      Rails.logger.error "FireCloud status error: #{e.message}"
      e.response
    end
  end

  # get health check on individual FireCloud services by name from FireCloudClient#api_status
  # Should not be used to assess overall API health, but rather a quick thumbs up/down on a specific service
  #
  # * *params*
  #   #   - +services+ (Array) => array of service names (from api_status['systems']), passed with splat operator, so should not be an actual array
  # * *return*
  #   - +Boolean+ indication of availability of requested FireCloud service
  def services_available?(*services)
    api_status = self.api_status
    if api_status.is_a?(Hash)
      api_ok = true
      services.each do |service|
        if api_status['systems'].present? && api_status['systems'][service].present? && api_status['systems'][service]['ok']
          next
        else
          api_ok = false
          break
        end
      end
      api_ok
    else
      false
    end
  end

  ##
  ## WORKSPACE METHODS
  ##

  # return a list of all workspaces in a given namespace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #
  # * *return*
  #   - +Array+ of +Hash+ objects detailing workspaces
  def workspaces(workspace_namespace=PORTAL_NAMESPACE)
    path = self.api_root + '/api/workspaces'
    workspaces = process_firecloud_request(:get, path)
    workspaces.keep_if {|ws| ws['workspace']['namespace'] == workspace_namespace}
  end

  # get the specified workspace
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of workspace
  #
  # * *return*
  #   - +Hash+ object of workspace instance
  def get_workspace(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}"
    process_firecloud_request(:get, path)
  end

  ##
  ## WORKSPACE ENTITY METHODS
  ##

  # list workspace metadata entities with type and attribute information
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities_with_type"
    process_firecloud_request(:get, path)
  end

  # list workspace metadata entity types
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #
  # * *return*
  #   - +Array+ of workspace metadata entities
  def get_workspace_entity_types(workspace_namespace, workspace_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities"
    process_firecloud_request(:get, path)
  end

  # get a list workspace metadata entities of requested type
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities_by_type(workspace_namespace, workspace_name, entity_type)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}"
    process_firecloud_request(:get, path)
  end

  # get an individual workspace metadata entity
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #   - +entity_name+ (String) => name of requested entity
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entity(workspace_namespace, workspace_name, entity_type, entity_name)
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}/#{entity_name}"
    process_firecloud_request(:get, path)
  end


  # get a tsv file of requested workspace metadata entities of requested type
  #
  # * *params*
  #   - +workspace_namespace+ (String) => namespace of workspace
  #   - +workspace_name+ (String) => name of requested workspace
  #   - +entity_type+ (String) => type of requested entity
  #   - +entity_names+ (String) => list of requested entities to include in file (provide each as a separate parameter)
  #
  # * *return*
  #   - +Array+ of workspace metadata entities with type and attribute information
  def get_workspace_entities_as_tsv(workspace_namespace, workspace_name, entity_type, *attribute_names)
    attribute_list = attribute_names.join(',')
    path = self.api_root + "/api/workspaces/#{uri_encode(workspace_namespace)}/#{uri_encode(workspace_name)}/entities/#{entity_type}/tsv#{attribute_list.blank? ? nil : '?attributeNames=' + attribute_list}"
    process_firecloud_request(:get, path)
  end

  ##
  ## PROFILE/BILLING METHODS
  ##

  # get a user's profile status
  #
  # * *return*
  #   - +Hash+ of user registration properties, including email, userID and enabled features
  def get_registration
    path = self.api_root + '/register'
    process_firecloud_request(:get, path)
  end

  # register a new user or update a user's profile in FireCloud
  #
  # * *params*
  #   - +profile_contents+ (Hash) => complete FireCloud profile information, see https://api.firecloud.org/#!/Profile/setProfile for details
  #
  # * *return*
  #   - +Hash+ of user's registration status information (see FireCloudClient#registration)
  def set_profile(profile_contents)
    path = self.api_root + '/register/profile'
    process_firecloud_request(:post, path, profile_contents.to_json)
  end

  # get a user's profile status
  #
  # * *return*
  #   - +Hash+ of key/value pairs of information stored in a user's FireCloud profile
  def get_profile
    path = self.api_root + '/register/profile'
    process_firecloud_request(:get, path)
  end

  # check if a user is registered (via access token)
  #
  # * *return*
  #   - +Boolean+ indication of whether or not user is registered
  def registered?
    begin
      self.get_registration
      true
    rescue => e
      # any error should be treated as the user not being registered
      false
    end
  end

  #######
  ##
  ## GOOGLE CLOUD STORAGE METHODS
  ##
  ## All methods are convenience wrappers around google-cloud-storage methods
  ## see https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0 for more detail
  ##
  #######

  # generic handler to process GCS method with retries and error handling
  #
  # * *params*
  #   - +method_name+ (String, Symbol) => name of FireCloudClient GCS method to execute
  #   - +retry_count+ (Integer) => current count of number of retries.  defaults to 0 and self-increments
  #   - +params+ (Array) => array of method parameters (passed with splat operator, so does not need to be an actual array)
  #
  # * *return*
  #   - Object depends on method, can be one of the following: +Google::Cloud::Storage::Bucket+, +Google::Cloud::Storage::File+,
  #     +Google::Cloud::Storage::FileList+, +Boolean+, +File+, or +String+
  #
  # * *raises*
  #   - (Exception)
  def execute_gcloud_method(method_name, retry_count=0, *params)
    begin
      self.send(method_name, *params)
    rescue => e
      current_retry = retry_count + 1
      Rails.logger.error "error calling #{method_name} with #{params.join(', ')}; #{e.message} -- attempt ##{current_retry}"
      retry_time = retry_count * RETRY_INTERVAL
      sleep(retry_time) unless RETRY_BACKOFF_BLACKLIST.include?(method_name)
      # only retry if status code indicates a possible temporary error, and we are under the retry limit and
      # not calling a method that is blocked from retries.  In case of a NoMethodError or RuntimeError, use 500 as the
      # status code since these are unrecoverable errors
      if e.respond_to?(:code)
        status_code = e.code
      elsif e.is_a?(NoMethodError) || e.is_a?(RuntimeError)
        status_code = 500
      else
        status_code = nil
      end
      if should_retry?(status_code) && retry_count < MAX_RETRY_COUNT && !ERROR_IGNORE_LIST.include?(method_name)
        execute_gcloud_method(method_name, current_retry, *params)
      else
        # we have reached our retry limit or the response code indicates we should not retry
        Rails.logger.error "Retry count exceeded calling #{method_name} with #{params.join(', ')}: #{e.message}"
        raise e
      end
    end
  end

  # retrieve a workspace's GCP bucket
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #
  # * *return*
  #   - +Google::Cloud::Storage::Bucket+ object
  def get_workspace_bucket(workspace_bucket_id)
    self.storage.bucket workspace_bucket_id
  end

  # retrieve all files in a GCP bucket of a workspace
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +opts+ (Hash) => hash of optional parameters, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/bucket?method=files-instance
  #
  # * *return*
  #   - +Google::Cloud::Storage::File::List+
  def get_workspace_files(workspace_bucket_id, opts={})
    bucket = self.get_workspace_bucket(workspace_bucket_id)
    bucket.files(opts)
  end

  # retrieve single study_file in a GCP bucket of a workspace
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +Google::Cloud::Storage::File+
  def get_workspace_file(workspace_bucket_id, filename)
    bucket = self.get_workspace_bucket(workspace_bucket_id)
    bucket.file filename
  end

  # read the contents of a file in a workspace bucket into memory
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +StringIO+ contents of workspace file
  def read_workspace_file(workspace_bucket_id, filename)
    file = self.get_workspace_file(workspace_bucket_id, filename)
    file_contents = file.download
    file_contents.rewind
    file_contents
  end

  # generate a signed url to download a file that isn't public (set at study level)
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #   - +opts+ (Hash) => extra options for signed_url, see
  #     https://googlecloudplatform.github.io/google-cloud-ruby/#/docs/google-cloud-storage/v1.13.0/google/cloud/storage/file?method=signed_url-instance
  #
  # * *return*
  #   - +String+ signed URL
  def generate_signed_url(workspace_bucket_id, filename, opts={})
    file = self.get_workspace_file(workspace_bucket_id, filename)
    file.signed_url(opts)
  end

  # generate an api url to directly load a file from GCS via client-side JavaScript
  #
  # * *params*
  #   - +workspace_bucket_id+ (String) => ID of workspace GCP bucket
  #   - +filename+ (String) => name of file
  #
  # * *return*
  #   - +String+ signed URL
  def generate_api_url(workspace_bucket_id, filename)
    file = self.get_workspace_file(workspace_bucket_id, filename)
    if file
      file.api_url + '?alt=media'
    else
      ''
    end
  end

  #######
  ##
  ## UTILITY METHODS
  ##
  #######

  # check if OK response code was found
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response is a known 'OK' response
  def ok?(code)
    [200, 201, 202, 204, 206].include?(code)
  end

  # determine if request should be retried based on response code
  #
  # * *params*
  #   - +code+ (Integer) => integer HTTP response code
  #
  # * *return*
  #   - +Boolean+ of whether or not response code indicates a retry should be executed
  def should_retry?(code)
    # if code is nil, we're not sure so retry anyway
    code.nil? || [502, 503].include?(code)
  end

  # merge hash of options into single URL query string
  #
  # * *params*
  #   - +opts+ (Hash) => hash of query parameter key/value pairs
  #
  # * *return*
  #   - +String+ of concatenated query params
  def merge_query_options(opts)
    # return nil if opts is empty, else concat
    opts.blank? ? nil : '?' + opts.to_a.map {|k,v| "#{k}=#{v}"}.join("&")
  end

  # handle a RestClient::Response object
  #
  # * *params*
  #   - +response+ (String) => an RestClient response object
  #
  # * *return*
  #   - +Hash+ if response body is JSON, or +String+ of original body
  def handle_response(response)
    begin
      if ok?(response.code)
        if response.body.present?
          parse_response_body(response.body)
        else
          true # blank body
        end
      else
        Rails.logger.error "Unexpected response #{response.code}, not sure what to do here..."
        response.message
      end
    rescue => e
      # don't report, just return
      response.message
    end
  end

  # parse a response body based on the content
  #
  # * *params*
  #   - +response_body+ (String) => an RestClient response body
  #
  # * *return*
  #   - +Hash+ if response body is JSON, or +String+ of original body
  def parse_response_body(response_body)
    is_json?(response_body) ? JSON.parse(response_body) : response_body
  end

  # determine if a response body is parseable as JSON
  #
  # * *params*
  #   - +content+ (String) => an RestClient response body
  #
  # * *return*
  #   - +Boolean+ indication if content is JSON
  def is_json?(content)
    if content.present?
      sanitized_content = content.gsub(/\n/, '') # remove newlines that may break this check
      chars = [sanitized_content[0], sanitized_content[sanitized_content.size - 1]]
      chars == %w({ }) || chars == %w([ ])
    else
      false
    end
  end

  # return a more user-friendly error message
  #
  # * *params*
  #   - +error+ (RestClient::Exception) => an RestClient error object
  #
  # * *return*
  #   - +String+ representation of complete error message, with http body if present
  def parse_error_message(error)
    if error.http_body.blank? || !is_json?(error.http_body)
      error.message
    else
      begin
        error_hash = JSON.parse(error.http_body)
        if error_hash.has_key?('message')
          # check if hash can be parsed further
          message = error_hash['message']
          if message.index('{').nil?
            return message
          else
            # attempt to extract nested JSON from message
            json_start = message.index('{')
            json = message[json_start, message.size + 1]
            new_message = JSON.parse(json)
            if new_message.has_key?('message')
              new_message['message']
            else
              new_message
            end
          end
        else
          return error.message
        end
      rescue => e
        # reporting error doesn't help, so ignore
        Rails.logger.error e.message
        error.message + ': ' + error.http_body
      end
    end
  end

  # URI-encode workspace identifiers (namespaces, workspaces) for use in API requests
  #
  # * *params*
  #   - +identifier+ (String) => Name of Terra namespace/workspace
  #
  # * *returns*
  #   - +String+ => URI-encoded namespace/workspace
  def uri_encode(identifier)
    URI.escape(identifier)
  end
end
