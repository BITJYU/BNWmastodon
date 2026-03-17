# frozen_string_literal: true

class Auth::AccountSwitchesController < ApplicationController
  include MultiAccountSession

  before_action :authenticate_user!

  def create
    target_id = switch_params[:account_id].to_i
    stored_sessions = prune_inactive_account_sessions(session)
    target_session = find_account_session(session, target_id)

    if target_session.nil?
      render json: { error: 'unauthorized' }, status: :forbidden
      return
    end

    target_user = User.find_by(id: target_session['user_id'], account_id: target_id)
    target_activation = SessionActivation.find_by(session_id: target_session['session_id'], user_id: target_user&.id)

    if target_user.nil? || target_activation.nil?
      remove_account_session(session, target_id)
      render json: { error: 'unauthorized' }, status: :forbidden
      return
    end

    write_auth_session_id(session, target_session['session_id'])
    sign_in(:user, target_user)
    write_stored_account_sessions(session, stored_sessions)
    render json: { ok: true }
  end

  def destroy
    current_account_id = current_user.account_id
    current_session_id = current_auth_session_id(session)
    remaining_sessions = remove_account_session(session, current_account_id)

    SessionActivation.deactivate(current_session_id) if current_session_id.present?

    previous_session = remaining_sessions.reverse.find do |entry|
      SessionActivation.active?(entry['session_id'])
    end

    if previous_session
      previous_user = User.find_by(id: previous_session['user_id'], account_id: previous_session['account_id'])

      if previous_user
        write_auth_session_id(session, previous_session['session_id'])
        sign_in(:user, previous_user)
        write_stored_account_sessions(session, remaining_sessions)
        redirect_to root_path
        return
      end
    end

    clear_auth_session_id(session)
    sign_out(current_user)

    redirect_to root_path
  end

  private

  def switch_params
    params.require(:account_switch).permit(:account_id)
  end
end
