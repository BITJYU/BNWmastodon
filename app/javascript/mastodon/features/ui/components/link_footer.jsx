import { PureComponent } from 'react';

import { FormattedMessage } from 'react-intl';

import { Link } from 'react-router-dom';

import { source_url } from 'mastodon/initial_state';

class LinkFooter extends PureComponent {

  render () {
    const DividingCircle = <span aria-hidden>{' · '}</span>;

    return (
      <div className='link-footer'>
        <p>
          <strong>Mastodon</strong>:
          {' '}
          <a href='https://joinmastodon.org' target='_blank'><FormattedMessage id='footer.about' defaultMessage='About' /></a>
          {DividingCircle}
          <a href='https://joinmastodon.org/apps' target='_blank'><FormattedMessage id='footer.get_app' defaultMessage='Get the app' /></a>
          {DividingCircle}
          <Link to='/keyboard-shortcuts'><FormattedMessage id='footer.keyboard_shortcuts' defaultMessage='Keyboard shortcuts' /></Link>
          {DividingCircle}
          <a href={source_url} rel='noopener noreferrer' target='_blank'><FormattedMessage id='footer.source_code' defaultMessage='View source code' /></a>
        </p>
      </div>
    );
  }

}

export default LinkFooter;
