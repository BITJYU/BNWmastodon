import PropTypes from 'prop-types';
import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { defineMessages, useIntl } from 'react-intl';
import { useSelector } from 'react-redux';
import {
  getStoredAccounts,
  removeStoredAccount,
  syncStoredAccountsAcrossTabs,
  updateUnreadCount,
  upsertStoredAccount,
} from '../../../utils/stored_accounts';

const SWITCH_ERROR_MESSAGE = 'Failed to switch accounts. Please try again.';
const LOAD_ERROR_MESSAGE = 'Could not load saved accounts.';

const messages = defineMessages({
  switchAccounts: { id: 'account_switcher.switch_accounts', defaultMessage: 'Switch accounts' },
  loadingAccounts: { id: 'account_switcher.loading', defaultMessage: 'Loading saved accounts...' },
  noAccounts: { id: 'account_switcher.empty', defaultMessage: 'No saved accounts available.' },
  addAccount: { id: 'account_switcher.add_account', defaultMessage: 'Add another account' },
  logOutCurrent: { id: 'account_switcher.logout_current', defaultMessage: 'Log out @{acct}' },
});

const mergeAccountsWithLocalState = (accounts, cachedAccounts, hiddenAccountIds) => {
  const cachedAccountsById = new Map(cachedAccounts.map(account => [String(account.id), account]));

  return accounts
    .filter(account => !hiddenAccountIds.includes(String(account.id)))
    .map(account => {
      const cachedAccount = cachedAccountsById.get(String(account.id));

      return {
        ...account,
        unread_count: cachedAccount?.unread_count ?? 0,
      };
    });
};

const AccountSwitcher = ({ variant = 'default', onClose, panelStyle }) => {
  const intl = useIntl();
  const me = useSelector(state => state.getIn(['meta', 'me']));
  const account = useSelector(state => state.getIn(['accounts', me]));
  const unreadCount = useSelector(state => state.getIn(['notifications', 'unreadCount'], 0));

  const [isOpen, setIsOpen] = useState(false);
  const [storedAccounts, setStoredAccounts] = useState(() => getStoredAccounts());
  const [serverAccounts, setServerAccounts] = useState([]);
  const [hiddenAccountIds, setHiddenAccountIds] = useState([]);
  const [errorMessage, setErrorMessage] = useState(null);
  const [loadErrorMessage, setLoadErrorMessage] = useState(null);
  const [isLoadingAccounts, setIsLoadingAccounts] = useState(false);

  const containerRef = useRef(null);

  const currentId = account?.get('id');
  const currentAcct = account?.get('acct');
  const currentAvatar = account?.get('avatar');
  const currentDisplayName = account?.get('display_name');
  const currentLocked = account?.get('locked');
  const isPanelOnly = variant === 'panel';
  const switchAccountsLabel = intl.formatMessage(messages.switchAccounts);
  const isRenderedOpen = isPanelOnly || isOpen;

  const closeSwitcher = () => {
    if (isPanelOnly) {
      onClose?.();
    } else {
      setIsOpen(false);
    }
  };

  useEffect(() => {
    const cleanup = syncStoredAccountsAcrossTabs(setStoredAccounts);
    return cleanup;
  }, []);

  useEffect(() => {
    if (!account) return;

    upsertStoredAccount({
      id: account.get('id'),
      acct: account.get('acct'),
      display_name: account.get('display_name'),
      avatar: account.get('avatar'),
      locked: account.get('locked'),
      unread_count: unreadCount,
    });

    setStoredAccounts(getStoredAccounts());
  }, [account, unreadCount]);

  useEffect(() => {
    if (!isRenderedOpen) return;

    let cancelled = false;

    const loadAccounts = async () => {
      setIsLoadingAccounts(true);
      setLoadErrorMessage(null);

      try {
        const response = await fetch('/api/v1/account_switcher', {
          credentials: 'same-origin',
          headers: {
            Accept: 'application/json',
          },
        });

        if (!response.ok) throw new Error('failed to load account switcher accounts');

        const body = await response.json();
        if (!cancelled) {
          setServerAccounts(Array.isArray(body.accounts) ? body.accounts : []);
        }
      } catch {
        if (!cancelled) {
          setServerAccounts([]);
          setLoadErrorMessage(LOAD_ERROR_MESSAGE);
        }
      } finally {
        if (!cancelled) {
          setIsLoadingAccounts(false);
        }
      }
    };

    loadAccounts();

    const handleMouseDown = event => {
      if (containerRef.current && !containerRef.current.contains(event.target)) {
        closeSwitcher();
      }
    };

    document.addEventListener('mousedown', handleMouseDown);
    return () => {
      cancelled = true;
      document.removeEventListener('mousedown', handleMouseDown);
    };
  }, [isRenderedOpen, isPanelOnly, onClose]);

  useEffect(() => {
    if (!isRenderedOpen) return;

    const handleKeyDown = event => {
      if (event.key === 'Escape') closeSwitcher();
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isRenderedOpen, isPanelOnly, onClose]);

  const handleSwitch = async targetId => {
    if (!currentId) return;

    updateUnreadCount(currentId, unreadCount);
    setErrorMessage(null);

    try {
      const formData = new FormData();
      formData.append('account_switch[account_id]', targetId);

      const response = await fetch('/auth/account/switch', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content ?? '',
        },
        body: formData,
        credentials: 'same-origin',
      });

      if (response.ok) {
        window.location.href = '/';
      } else {
        setErrorMessage(SWITCH_ERROR_MESSAGE);
      }
    } catch {
      setErrorMessage(SWITCH_ERROR_MESSAGE);
    }
  };

  const handleRemove = id => {
    if (String(id) === String(currentId)) return;

    removeStoredAccount(id);
    setHiddenAccountIds(previousIds => (previousIds.includes(String(id)) ? previousIds : [...previousIds, String(id)]));
    setStoredAccounts(previousAccounts => previousAccounts.filter(accountItem => String(accountItem.id) !== String(id)));
    setServerAccounts(previousAccounts => previousAccounts.filter(accountItem => String(accountItem.id) !== String(id)));
  };

  const renderedAccounts = mergeAccountsWithLocalState(serverAccounts, storedAccounts, hiddenAccountIds);
  const panelMarkup = isRenderedOpen ? (
    <div
      className={`account-switcher__panel${isPanelOnly ? ' account-switcher__panel--side account-switcher__panel--floating' : ''}`}
      role='listbox'
      aria-label={switchAccountsLabel}
      style={isPanelOnly ? panelStyle : undefined}
    >
      {isLoadingAccounts ? (
        <p className='account-switcher__error' role='status'>
          {intl.formatMessage(messages.loadingAccounts)}
        </p>
      ) : (
        <ul className='account-switcher__list'>
          {renderedAccounts.map(storedAccount => {
            const isCurrentAccount = Boolean(storedAccount.current) || String(storedAccount.id) === String(currentId);

            return (
              <li key={storedAccount.id} className='account-switcher__item-row'>
                <button
                  className={`account-switcher__item${isCurrentAccount ? ' account-switcher__item--active' : ''}`}
                  onClick={() => !isCurrentAccount && handleSwitch(storedAccount.id)}
                  disabled={isCurrentAccount}
                  aria-current={isCurrentAccount ? 'true' : undefined}
                >
                  <div className='account-switcher__item-avatar-wrap'>
                    <img className='account-switcher__item-avatar' src={storedAccount.avatar} alt='' />
                    {isCurrentAccount && (
                      <span className='account-switcher__item-check' aria-label='Current account'>
                        OK
                      </span>
                    )}
                  </div>

                  <div className='account-switcher__item-info'>
                    <span className='account-switcher__item-display-name'>
                      {storedAccount.display_name}
                      {storedAccount.locked && (
                        <span className='account-switcher__item-lock' aria-label='Locked account'>
                          Lock
                        </span>
                      )}
                    </span>
                    <span className='account-switcher__item-acct'>@{storedAccount.acct}</span>
                  </div>

                  {!isCurrentAccount && storedAccount.unread_count > 0 && (
                    <span
                      className='account-switcher__item-unread'
                      aria-label={`${storedAccount.unread_count} unread notifications`}
                    >
                      {storedAccount.unread_count}
                    </span>
                  )}
                </button>

                {!isCurrentAccount && (
                  <button
                    className='account-switcher__item-remove'
                    onClick={() => handleRemove(storedAccount.id)}
                    aria-label={`Remove @${storedAccount.acct} from this list`}
                  >
                    x
                  </button>
                )}
              </li>
            );
          })}

          {!renderedAccounts.length && !loadErrorMessage && (
            <li className='account-switcher__item-row'>
              <p className='account-switcher__error' role='status'>
                {intl.formatMessage(messages.noAccounts)}
              </p>
            </li>
          )}
        </ul>
      )}

      {loadErrorMessage && (
        <p className='account-switcher__error' role='alert'>
          {loadErrorMessage}
        </p>
      )}

      {errorMessage && (
        <p className='account-switcher__error' role='alert'>
          {errorMessage}
        </p>
      )}

      <div className='account-switcher__footer'>
        <a href='/auth/sign_in?add_account=true' className='account-switcher__footer-link'>
          {intl.formatMessage(messages.addAccount)}
        </a>
        <a
          href='/auth/sign_out'
          className='account-switcher__footer-link account-switcher__footer-link--logout'
          data-method='delete'
        >
          {intl.formatMessage(messages.logOutCurrent, { acct: currentAcct })}
        </a>
      </div>
    </div>
  ) : null;

  if (isPanelOnly) {
    return createPortal(
      <div className='account-switcher account-switcher--menu account-switcher--portal' ref={containerRef}>
        {panelMarkup}
      </div>,
      document.body
    );
  }

  return (
    <div className='account-switcher' ref={containerRef}>
      {panelMarkup}

      {!isPanelOnly && (
        <button
          className='account-switcher__trigger'
          onClick={() => setIsOpen(open => !open)}
          aria-expanded={isOpen}
          aria-haspopup='listbox'
        >
          <img className='account-switcher__trigger-avatar' src={currentAvatar} alt='' />
          <div className='account-switcher__trigger-info'>
            <span className='account-switcher__trigger-name'>
              {currentDisplayName}
              {currentLocked && <span aria-label='Locked account'> Lock</span>}
            </span>
            <span className='account-switcher__trigger-acct'>@{currentAcct}</span>
          </div>
          <span className='account-switcher__dots' aria-hidden='true'>
            ...
          </span>
        </button>
      )}
    </div>
  );
};

AccountSwitcher.propTypes = {
  variant: PropTypes.oneOf(['default', 'panel']),
  onClose: PropTypes.func,
  panelStyle: PropTypes.object,
};

export default AccountSwitcher;
