import PropTypes from 'prop-types';
import { PureComponent } from 'react';

import { defineMessages, injectIntl } from 'react-intl';

import ImmutablePropTypes from 'react-immutable-proptypes';
import DropdownMenuContainer from '../../../containers/dropdown_menu_container';
import AccountSwitcher from '../../ui/components/account_switcher';

const messages = defineMessages({
  edit_profile: { id: 'account.edit_profile', defaultMessage: 'Edit profile' },
  pins: { id: 'navigation_bar.pins', defaultMessage: 'Pinned posts' },
  directMessages: { id: 'navigation_bar.directMessages', defaultMessage: 'Direct Messages' },
  switchAccounts: { id: 'account_switcher.switch_accounts', defaultMessage: 'Switch accounts' },
  preferences: { id: 'navigation_bar.preferences', defaultMessage: 'Preferences' },
  follow_requests: { id: 'navigation_bar.follow_requests', defaultMessage: 'Follow requests' },
  favourites: { id: 'navigation_bar.favourites', defaultMessage: 'Favorites' },
  lists: { id: 'navigation_bar.lists', defaultMessage: 'Lists' },
  followed_tags: { id: 'navigation_bar.followed_tags', defaultMessage: 'Followed hashtags' },
  blocks: { id: 'navigation_bar.blocks', defaultMessage: 'Blocked users' },
  domain_blocks: { id: 'navigation_bar.domain_blocks', defaultMessage: 'Blocked domains' },
  mutes: { id: 'navigation_bar.mutes', defaultMessage: 'Muted users' },
  filters: { id: 'navigation_bar.filters', defaultMessage: 'Muted words' },
  logout: { id: 'navigation_bar.logout', defaultMessage: 'Logout' },
  bookmarks: { id: 'navigation_bar.bookmarks', defaultMessage: 'Bookmarks' },
});

class ActionBar extends PureComponent {

  state = {
    accountSwitcherOpen: false,
    accountSwitcherStyle: null,
  };

  static propTypes = {
    account: ImmutablePropTypes.map.isRequired,
    onLogout: PropTypes.func.isRequired,
    intl: PropTypes.object.isRequired,
  };

  handleLogout = () => {
    this.props.onLogout();
  };

  closeAccountSwitcher = () => {
    this.setState({ accountSwitcherOpen: false, accountSwitcherStyle: null });
  };

  handleAccountSwitcherAction = e => {
    e.preventDefault();
    e.stopPropagation();

    if (this.state.accountSwitcherOpen) {
      this.closeAccountSwitcher();
      return;
    }

    const target = e.currentTarget;
    const triggerRect = target.getBoundingClientRect();
    const dropdownPanel =
      target.closest('.dropdown-menu') ||
      target.closest('[role="menu"]') ||
      target.closest('.dropdown-menu__container');
    const anchorRect = dropdownPanel ? dropdownPanel.getBoundingClientRect() : triggerRect;
    const panelWidth = 220;
    const panelHeight = 272;
    const margin = 8;
    const viewportHeight = window.innerHeight;

    const left = Math.max(margin, anchorRect.left - panelWidth);
    const top = Math.max(margin, Math.min(triggerRect.top, viewportHeight - panelHeight - margin));

    this.setState({
      accountSwitcherOpen: true,
      accountSwitcherStyle: {
        left: `${Math.round(left)}px`,
        top: `${Math.round(top)}px`,
      },
    });
  };

  render () {
    const { intl } = this.props;
    const username = this.props.account.get('acct')
    let menu = [];

    menu.push({ text: intl.formatMessage(messages.edit_profile), href: '/settings/profile' });
    menu.push({ text: intl.formatMessage(messages.preferences), href: '/settings/preferences' });
    menu.push({ text: intl.formatMessage(messages.pins), to: '/pinned' });
    menu.push(null);
    menu.push({ text: intl.formatMessage(messages.directMessages), to:`/@${username}/direct_messages` });
    menu.push({
      text: intl.formatMessage(messages.switchAccounts),
      action: this.handleAccountSwitcherAction,
      keepOpen: true,
    });
    menu.push(null);
    menu.push({ text: intl.formatMessage(messages.follow_requests), to: '/follow_requests' });
    menu.push({ text: intl.formatMessage(messages.favourites), to: '/favourites' });
    menu.push({ text: intl.formatMessage(messages.bookmarks), to: '/bookmarks' });
    menu.push({ text: intl.formatMessage(messages.lists), to: '/lists' });
    menu.push({ text: intl.formatMessage(messages.followed_tags), to: '/followed_tags' });
    menu.push(null);
    menu.push({ text: intl.formatMessage(messages.mutes), to: '/mutes' });
    menu.push({ text: intl.formatMessage(messages.blocks), to: '/blocks' });
    menu.push({ text: intl.formatMessage(messages.domain_blocks), to: '/domain_blocks' });
    menu.push({ text: intl.formatMessage(messages.filters), href: '/filters' });
    menu.push(null);
    menu.push({ text: intl.formatMessage(messages.logout), action: this.handleLogout });

    return (
      <div className='compose__action-bar'>
        <div className='compose__action-bar-dropdown'>
          <DropdownMenuContainer items={menu} icon='bars' size={18} direction='right' />
        </div>

        {this.state.accountSwitcherOpen && (
          <AccountSwitcher
            variant='panel'
            panelStyle={this.state.accountSwitcherStyle}
            onClose={this.closeAccountSwitcher}
          />
        )}
      </div>
    );
  }

}

export default injectIntl(ActionBar);
