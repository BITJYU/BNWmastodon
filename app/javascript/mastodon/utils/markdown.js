import escapeTextContentForBrowser from 'escape-html';

const BOLD_REGEX = /(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)/gs;
const ITALIC_REGEX = /(?<!\*)\*(?=\S)(.+?)(?<=\S)\*(?!\*)/gs;
const SKIPPED_TAGS = new Set(['A', 'CODE', 'PRE', 'SCRIPT', 'STYLE', 'TEXTAREA']);

const formatMarkdownText = text => {
  let html = escapeTextContentForBrowser(text);

  html = html.replace(BOLD_REGEX, '<strong>$1</strong>');
  html = html.replace(ITALIC_REGEX, '<em>$1</em>');

  return html;
};

const replaceTextNode = node => {
  const html = formatMarkdownText(node.textContent);

  if (html === escapeTextContentForBrowser(node.textContent)) {
    return;
  }

  const template = document.createElement('template');
  template.innerHTML = html;

  const fragment = document.createDocumentFragment();

  while (template.content.firstChild) {
    fragment.appendChild(template.content.firstChild);
  }

  node.replaceWith(fragment);
};

const walkNodes = node => {
  Array.from(node.childNodes).forEach(child => {
    if (child.nodeType === Node.TEXT_NODE) {
      replaceTextNode(child);
      return;
    }

    if (child.nodeType === Node.ELEMENT_NODE && !SKIPPED_TAGS.has(child.tagName)) {
      walkNodes(child);
    }
  });
};

const formatMarkdown = html => {
  const wrapper = document.createElement('div');
  wrapper.innerHTML = html;
  walkNodes(wrapper);
  return wrapper.innerHTML;
};

export default formatMarkdown;
