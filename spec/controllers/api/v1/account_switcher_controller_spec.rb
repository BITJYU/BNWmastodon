# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AccountSwitcherController do
  render_views

  let(:user) { Fabricate(:user, account_attributes: { username: 'owner', display_name: 'Owner Live' }) }
  let(:other_user) { Fabricate(:user, account_attributes: { username: 'owner2', display_name: 'Owner Two Live' }) }
  let(:stale_user) { Fabricate(:user, account_attributes: { username: 'stale', display_name: 'Stale User' }) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: 'read') }

  let!(:current_activation) { Fabricate(:session_activation, user: user, session_id: 'session-owner') }
  let!(:other_activation) { Fabricate(:session_activation, user: other_user, session_id: 'session-owner2') }

  before do
    allow(controller).to receive(:doorkeeper_token) { token }

    session[:stored_account_sessions] = [
      {
        'account_id' => user.account_id,
        'user_id' => user.id,
        'session_id' => current_activation.session_id,
        'acct' => 'stale-owner',
        'display_name' => 'Stale owner name',
        'avatar' => 'https://example.test/old-owner.png',
        'locked' => false,
      },
      {
        'account_id' => other_user.account_id,
        'user_id' => other_user.id,
        'session_id' => other_activation.session_id,
        'acct' => 'stale-owner2',
        'display_name' => 'Stale owner two',
        'avatar' => 'https://example.test/old-owner2.png',
        'locked' => false,
      },
      {
        'account_id' => stale_user.account_id,
        'user_id' => stale_user.id,
        'session_id' => 'inactive-session',
        'acct' => 'stale',
        'display_name' => 'Stale inactive',
        'avatar' => 'https://example.test/stale.png',
        'locked' => false,
      },
    ]
  end

  describe 'GET #show' do
    it 'returns active server-authoritative accounts and cleans stale entries', :aggregate_failures do
      get :show

      expect(response).to have_http_status(200)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(body_as_json[:accounts].pluck(:id)).to contain_exactly(user.account_id.to_s, other_user.account_id.to_s)

      current_account = body_as_json[:accounts].find { |account| account[:id] == user.account_id.to_s }
      other_account = body_as_json[:accounts].find { |account| account[:id] == other_user.account_id.to_s }

      expect(current_account[:display_name]).to eq('Owner Live')
      expect(current_account[:acct]).to eq('owner')
      expect(current_account[:current]).to be(true)
      expect(other_account[:display_name]).to eq('Owner Two Live')
      expect(other_account[:acct]).to eq('owner2')
      expect(other_account[:current]).to be(false)

      expect(session[:stored_account_sessions].pluck('account_id')).to contain_exactly(user.account_id, other_user.account_id)
    end
  end

  context 'without an oauth token' do
    before do
      allow(controller).to receive(:doorkeeper_token).and_return(nil)
    end

    it 'returns http unauthorized' do
      get :show

      expect(response).to have_http_status(401)
    end
  end
end
