# frozen_string_literal: true

class Auth::SessionsController < Devise::SessionsController
  include MultiAccountSession
  layout 'auth'

  skip_before_action :require_no_authentication, only: [:new, :create]
  skip_before_action :require_functional!
  skip_before_action :update_user_sign_in

  prepend_before_action :check_suspicious!, only: [:create]

  include TwoFactorAuthenticationConcern

  before_action :set_instance_presenter, only: [:new]
  before_action :set_body_classes
  before_action :preserve_existing_accounts_for_add_account, only: :new

  content_security_policy only: :new do |p|
    p.form_action(false)
  end

  def check_suspicious!
    user = find_user
    @login_is_suspicious = suspicious_sign_in?(user) unless user.nil?
  end

  def create
    preserved_sessions = merge_account_sessions(
      stored_account_sessions(session),
      pending_stored_account_sessions
    )

    self.resource = authenticate_session_resource
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)

    on_authentication_success(resource, :password, preserved_sessions) unless @on_authentication_success_called

    yield resource if block_given?
    respond_with resource, location: after_sign_in_path_for(resource)
  end

  def destroy
    tmp_stored_location = stored_location_for(:user)
    super
    session.delete(:challenge_passed_at)
    flash.delete(:notice)
    store_location_for(:user, tmp_stored_location) if continue_after?
  end

  def webauthn_options
    user = User.find_by(id: session[:attempt_user_id])

    if user&.webauthn_enabled?
      options_for_get = WebAuthn::Credential.options_for_get(
        allow: user.webauthn_credentials.pluck(:external_id),
        user_verification: 'discouraged'
      )

      session[:webauthn_challenge] = options_for_get.challenge

      render json: options_for_get, status: 200
    else
      render json: { error: t('webauthn_credentials.not_enabled') }, status: 401
    end
  end

  protected

  def find_user
    if user_params[:email].present?
      find_user_from_params
    elsif session[:attempt_user_id]
      User.find_by(id: session[:attempt_user_id])
    end
  end

  def find_user_from_params
    user   = User.authenticate_with_ldap(user_params) if Devise.ldap_authentication
    user ||= User.authenticate_with_pam(user_params) if Devise.pam_authentication
    user ||= User.find_for_authentication(email: user_params[:email])
    user
  end

  def user_params
    params.require(:user).permit(:email, :password, :otp_attempt, credential: {})
  end

  def after_sign_in_path_for(resource)
    last_url = stored_location_for(:user)

    if home_paths(resource).include?(last_url)
      root_path
    else
      last_url || root_path
    end
  end

  def require_no_authentication
    super

    # Delete flash message that isn't entirely useful and may be confusing in
    # most cases because /web doesn't display/clear flash messages.
    flash.delete(:alert) if flash[:alert] == I18n.t('devise.failure.already_authenticated')
  end

  private

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end

  def set_body_classes
    @body_classes = 'lighter'
  end

  def preserve_existing_accounts_for_add_account
    return unless truthy_param?(:add_account)
    return unless current_user

    current_session_id = current_session&.session_id || current_auth_session_id(session)
    return if current_session_id.blank?

    preserved_sessions = merge_account_sessions(
      stored_account_sessions(session),
      [account_session_payload(current_user, current_session_id)]
    )

    write_pending_stored_account_sessions(preserved_sessions)
  end

  def home_paths(resource)
    paths = [about_path, '/explore']

    paths << short_account_path(username: resource.account) if single_user_mode? && resource.is_a?(User)

    paths
  end

  def continue_after?
    truthy_param?(:continue)
  end

  def restart_session
    clear_attempt_from_session
    redirect_to new_user_session_path, alert: I18n.t('devise.failure.timeout')
  end

  def register_attempt_in_session(user)
    session[:attempt_user_id]         = user.id
    session[:attempt_user_updated_at] = user.updated_at.to_s
  end

  def clear_attempt_from_session
    session.delete(:attempt_user_id)
    session.delete(:attempt_user_updated_at)
  end

  def authenticate_session_resource
    return warden.authenticate!(auth_options) unless truthy_param?(:add_account)

    strategies = Devise.warden_config.default_strategies(scope: resource_name).uniq - [:session_activation_rememberable]

    clear_authenticated_user_scope(resource_name)
    warden.authenticate!(*strategies, auth_options)
  end

  def clear_authenticated_user_scope(scope)
    warden.session_serializer.delete(scope)
    session.delete("warden.user.#{scope}.session")
    session.delete("warden.user.#{scope}.key")

    users = warden.instance_variable_get(:@users)
    users[scope] = nil if users
    users[scope.to_s] = nil if users&.key?(scope.to_s)

    warden.clear_strategies_cache!(scope: scope)
  end

  def on_authentication_success(user, security_measure, preserved_sessions = nil)
    @on_authentication_success_called = true

    clear_attempt_from_session
    stored_sessions = merge_account_sessions(
      preserved_sessions || [],
      stored_account_sessions(session),
      pending_stored_account_sessions
    )

    user.update_sign_in!(new_sign_in: true)
    session_id = user.session_activations.order(created_at: :desc).pick(:session_id)
    merged_sessions = stored_sessions

    merged_sessions = merged_sessions.reject { |entry| entry['account_id'] == user.account_id }
    merged_sessions << account_session_payload(user, session_id) if session_id.present?

    write_auth_session_id(session, session_id) if session_id.present?
    write_stored_account_sessions(session, merged_sessions)
    clear_pending_stored_account_sessions
    flash.delete(:notice)

    LoginActivity.create(
      user: user,
      success: true,
      authentication_method: security_measure,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    UserMailer.suspicious_sign_in(user, request.remote_ip, request.user_agent, Time.now.utc).deliver_later! if @login_is_suspicious
  end

  def suspicious_sign_in?(user)
    SuspiciousSignInDetector.new(user).suspicious?(request)
  end

  def on_authentication_failure(user, security_measure, failure_reason)
    LoginActivity.create(
      user: user,
      success: false,
      authentication_method: security_measure,
      failure_reason: failure_reason,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
  end
end
