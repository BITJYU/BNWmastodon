# frozen_string_literal: true

class Api::V1::AccountSwitcherController < Api::BaseController
  include MultiAccountSession

  before_action :require_authenticated_user!

  def show
    response.headers['Cache-Control'] = 'no-store'

    raw_entries = stored_account_sessions(session)
    live_entries = active_account_sessions(session)
    users_by_id = load_users_by_id(live_entries)

    valid_entries = live_entries.select do |entry|
      user = users_by_id[entry['user_id']]
      user.present? && user.account_id == entry['account_id']
    end

    cleanup_stale_entries(valid_entries) if valid_entries.length != raw_entries.length

    Rails.logger.info(
      "[account_switcher] api_show current_account_id=#{current_user.account_id} " \
      "raw_account_ids=#{raw_entries.pluck('account_id').join(',')} " \
      "live_account_ids=#{valid_entries.pluck('account_id').join(',')}"
    )

    render json: {
      accounts: valid_entries.filter_map do |entry|
        user = users_by_id[entry['user_id']]
        account = user&.account
        next if account.nil?

        {
          id: account.id.to_s,
          acct: account.acct,
          display_name: account.display_name.presence || account.username,
          avatar: account.avatar_static_url,
          locked: account.locked?,
          current: current_user.account_id == account.id,
        }
      end,
    }
  end

  private

  def load_users_by_id(entries)
    user_ids = entries.pluck('user_id').uniq
    User.includes(:account).where(id: user_ids).index_by(&:id)
  end

  def cleanup_stale_entries(valid_entries)
    # Intentional side effect: remove stale saved-session entries.
    # Cleanup is best-effort; response should still succeed with valid entries only.
    write_stored_account_sessions(session, valid_entries)
  rescue StandardError => e
    Rails.logger.warn("[account_switcher_api] stale_entry_cleanup_failed=#{e.class}")
  end
end
