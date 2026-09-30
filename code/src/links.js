import { syntaxTree } from '@codemirror/language';
import { sendToApp } from './native.js';

export function openLink(view, href) {
  if (/^(https?:|mailto:)/i.test(href)) sendToApp('openLink', { url: href });
  else if (href.startsWith('#')) {
    const wanted = decodeURIComponent(href.slice(1));
    syntaxTree(view.state).iterate({
      enter(node) {
        if (/^(ATX|Setext)Heading/.test(node.name)) {
          const text = view.state.doc
            .sliceString(node.from, node.to)
            .replace(/^#+\s*|\n[=-]+$/g, '')
            .trim();
          const slug = text
            .toLowerCase()
            .replace(/[^\p{L}\p{N}\s_-]/gu, '')
            .replace(/\s+/g, '-');
          if (slug === wanted) {
            view.dispatch({ selection: { anchor: node.from }, scrollIntoView: true });
            view.focus();
          }
        }
      },
    });
  } else if (href && !/^[a-z][a-z0-9+.-]*:/i.test(href)) sendToApp('openRelative', { path: href });
}
