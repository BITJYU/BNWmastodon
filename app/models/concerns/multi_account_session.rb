# frozen_string_literal: true

module MultiAccountSession
  extend ActiveSupport::Concern

  STORED_ACCOUNT_SESSIONS_COOKIE = :stored_account_sessions
  PENDING_ACCOUNT_SESSIONS_COOKIE = :pending_stored_account_sessions
  AUTH_SESSION_COOKIE = :_session_id

  def store_account_in_session(session, user)
    session_id = current_auth_session_id(session)
    return if user.nil? || session_id.blank?

    upsert_account_session(session, user, session_id)
  end

  def remove_account_from_session(session, account_id)
    remove_account_session(session, account_id)
  end

  def stored_account_sessions(session)
    session_sessions = Array(session[:stored_account_sessions])
    cookie_sessions = respond_to?(:cookies) ? Array(cookies.signed[STORED_ACCOUNT_SESSIONS_COOKIE]) : []

    normalize_account_sessions(session_sessions + cookie_sessions)
  end

  def write_stored_account_sessions(session, account_sessions)
    normalized_sessions = normalize_account_sessions(account_sessions)
    session[:stored_account_sessions] = normalized_sessions

    return unless respond_to?(:cookies)

    cookies.signed[STORED_ACCOUNT_SESSIONS_COOKIE] = {
      value: normalized_sessions,
      expires: 1.year.from_now,
      httponly: true,
      same_site: :lax,
    }
  end

  def pending_stored_account_sessions
    session_sessions = respond_to?(:session) ? Array(session[:pending_stored_account_sessions]) : []
    cookie_sessions = respond_to?(:cookies) ? Array(cookies.signed[PENDING_ACCOUNT_SESSIONS_COOKIE]) : []

    normalize_account_sessions(session_sessions + cookie_sessions)
  end

  def write_pending_stored_account_sessions(account_sessions)
    normalized_sessions = normalize_account_sessions(account_sessions)
    session[:pending_stored_account_sessions] = normalized_sessions if respond_to?(:session)

    return unless respond_to?(:cookies)

    cookies.signed[PENDING_ACCOUNT_SESSIONS_COOKIE] = {
      value: normalized_sessions,
      expires: 1.hour.from_now,
      httponly: true,
      same_site: :lax,
    }
  end

  def clear_pending_stored_account_sessions
    session.delete(:pending_stored_account_sessions) if respond_to?(:session)
    return unless respond_to?(:cookies)

    cookies.delete(PENDING_ACCOUNT_SESSIONS_COOKIE)
  end

  def merge_account_sessions(*collections)
    normalize_account_sessions(collections.flatten)
  end

  def upsert_account_session(session, user, session_id)
    return [] if user.nil? || session_id.blank?

    merged_sessions = stored_account_sessions(session).reject { |entry| entry['account_id'] == user.account_id } << account_session_payload(user, session_id)
    write_stored_account_sessions(session, merged_sessions)
    merged_sessions
  end

  def remove_account_session(session, account_id)
    remaining_sessions = stored_account_sessions(session).reject { |entry| entry['account_id'] == account_id.to_i }
    write_stored_account_sessions(session, remaining_sessions)
    remaining_sessions
  end

  def find_account_session(session, account_id)
    stored_account_sessions(session).find { |entry| entry['account_id'] == account_id.to_i }
  end

  def active_account_sessions(session)
    stored_account_sessions(session).select { |entry| SessionActivation.active?(entry['session_id']) }
  end

  def prune_inactive_account_sessions(session)
    active_sessions = active_account_sessions(session)
    write_stored_account_sessions(session, active_sessions)
    active_sessions
  end

  def current_auth_session_id(session)
    if respond_to?(:cookies)
      cookies.signed[AUTH_SESSION_COOKIE].presence || session[:auth_id].presence
    else
      session[:auth_id].presence
    end
  end

  def write_auth_session_id(session, session_id)
    return if session_id.blank?

    session[:auth_id] = session_id

    return unless respond_to?(:cookies)

    cookies.signed[AUTH_SESSION_COOKIE] = {
      value: session_id,
      expires: 1.year.from_now,
      httponly: true,
      same_site: :lax,
    }
  end

  def clear_auth_session_id(session)
    session.delete(:auth_id)
    return unless respond_to?(:cookies)

    cookies.delete(AUTH_SESSION_COOKIE)
  end

  def account_session_payload(user, session_id)
    {
      'account_id' => user.account_id.to_i,
      'user_id' => user.id.to_i,
      'session_id' => session_id.to_s,
      'acct' => user.account.acct,
      'display_name' => user.account.display_name.presence || user.account.username,
      'avatar' => user.account.avatar_static_url,
      'locked' => user.account.locked?,
    }
  end

  def normalize_account_sessions(account_sessions)
    sessions_by_account = {}

    Array(account_sessions).each do |entry|
      next unless entry.is_a?(Hash)

      account_id = entry['account_id'] || entry[:account_id]
      user_id = entry['user_id'] || entry[:user_id]
      session_id = entry['session_id'] || entry[:session_id]
      next if account_id.blank? || user_id.blank? || session_id.blank?

      sessions_by_account[account_id.to_i] = {
        'account_id' => account_id.to_i,
        'user_id' => user_id.to_i,
        'session_id' => session_id.to_s,
        'acct' => (entry['acct'] || entry[:acct]).to_s,
        'display_name' => (entry['display_name'] || entry[:display_name]).to_s,
        'avatar' => (entry['avatar'] || entry[:avatar]).to_s,
        'locked' => ActiveModel::Type::Boolean.new.cast(entry['locked'] || entry[:locked]),
      }
    end

    sessions_by_account.values
  end
end
