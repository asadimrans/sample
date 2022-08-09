# rubocop:disable Metrics/ClassLength
class API < Grape::API
  prefix 'api'
  format :json

  before do
    result = SetTenantService.call url_type: :API, request: ActionDispatch::Request.new(env)
    Time.zone = current_property.local_time_zone if result.success?
    Rails.logger.error("No tenant could be set - #{result.message}") if result.failure?
  end

  # Rescue from syntax errors, etc, except when in the test environment
  unless Rails.env.test?
    rescue_from :all do |e|
      # Still need to be able to debug, lets log the error stack.
      Rails.logger.error e.message
      e.backtrace.each { |line| Rails.logger.error line }

      Rack::Response.new({ error_context: :application, error_code: :internal_server_error, error_message: e.message, error_fields: {} }.to_json, 500)
    end
  end

  rescue_from Grape::Exceptions::ValidationErrors do |e|
    Rack::Response.new({ error_context: :validation, error_code: :validation_errors, error_message: e.message, error_fields: {} }.to_json, 422)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    Rack::Response.new({ error_context: :db, error_code: :validation_errors, error_message: e.message, error_fields: {} }.to_json, 422)
  end

  rescue_from ActiveRecord::RecordNotFound do |e|
    Rack::Response.new({ error_context: :db, error_code: :record_not_found, error_message: e.message, error_fields: {} }.to_json, 422)
  end

  helpers Pundit
  after { verify_authorized unless request.get? }
  after { verify_policy_scoped if request.get? && !viewing_docs? }

  rescue_from Pundit::NotAuthorizedError do |e|
    custom_message = Current.pundit_error_code && I18n.t(Current.pundit_error_code, scope: :pundit)

    error_fields = custom_message.present? ? { policy_code: [Current.pundit_error_code] } : {}
    message = custom_message || e.message

    Rack::Response.new({ error_context: :policy, error_code: :authorization_error, error_message: message, error_fields: error_fields }.to_json, 422)
  end

  def self.auth_headers
    {
      "Authorization" => {
        description: "APIConsumer's jwt",
        required: true
      }
    }
  end

  helpers do
    def current_property
      ActsAsTenant.current_tenant
    end

    def viewing_docs?
      %r{/api/v[123]/docs}.match? request.path
    end

    def declared_params
      declared(params, include_missing: false)
    end

    def authenticate_request!
      fail! :auth, 401, "Failed to authenticate", status_code: 401 unless current_api_consumer

      # always include a valid auth token for next time for authenticated requests
      add_auth_header_to_response current_api_consumer
    end

    def add_auth_header_to_response(current_api_consumer)
      header 'X-Authentication', current_api_consumer.jwt
    end

    def current_api_consumer(allow_nil: false)
      @current_api_consumer ||= begin
        command = API::AuthenticateService.call(headers: request.headers)
        fail! :auth, command.code, command.message, {}, 403 unless allow_nil || command.success?
        command.api_consumer
      end
    end

    # Used by pundit
    def current_user
      @current_user ||= current_api_consumer(allow_nil: true)
    end

    def fail!(context, code, message = nil, error_fields = {}, status_code = 422)
      error_fields ||= {}
      message ||= I18n.t(code, scope: :api)
      Rails.logger.debug "context:#{context}, code:#{code}, message:#{message}, error_fields:#{error_fields}"
      failure_hash = { error_context: context, error_message: message, error_code: code.to_s, error_fields: error_fields }
      error! failure_hash, status_code
    end
  end

  before do
    # Configure defaults so we can access rails routes
    ActiveStorage::Current.host = request.base_url
    Rails.application.routes.default_url_options[:host] = request.base_url
  end

  mount V1::Root
end
# rubocop:enable Metrics/ClassLength
