import logoDark from 'mastodon/../images/bnw/logo_dark.png';
import logoLight from 'mastodon/../images/bnw/logo_light.png';

export const WordmarkLogo: React.FC = () => {
  return (
    <img src={logoLight} alt='BNW' className='logo logo--wordmark' />
  );
};

export const SymbolLogo: React.FC = () => (
  <img src={logoDark} alt='BNW' className='logo logo--icon' />
);
