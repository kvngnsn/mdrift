import { EditorState } from '@codemirror/state';
import { EditorView, keymap, drawSelection, placeholder } from '@codemirror/view';
import {
  markdown,
  markdownKeymap,
  markdownLanguage,
  insertNewlineContinueMarkupCommand,
} from '@codemirror/lang-markdown';
import {
  defaultKeymap,
  history,
  historyKeymap,
  indentWithTab,
  undo,
  redo,
  selectAll,
} from '@codemirror/commands';

import { isNativeApp, sendToApp } from './native.js';
import { openLink } from './links.js';
import { livePreviewExtensions } from './preview.js';

const elementById = (id) => document.getElementById(id);
document.body.classList.toggle('native', isNativeApp);
const welcome = `# mdrift

Read and write in the same place.

Click any line to edit. Move away and the Markdown becomes the page.

## plain text, live

A little **emphasis**, an *aside*, or a thought in \`code\`.

- No switching views
- No panels or toolbars
- Just your words

> One thing at a time.

Open a file with ⌘O. Save with ⌘S. Start fresh with ⌘N.
`;
let savedText = welcome;
let revision = 0;
let noticeTimer;
let currentPath = '';
let recoveryOkay = true;

function setTheme(value, persist = true) {
  const selected = value === 'light' ? 'light' : 'dark';
  document.documentElement.dataset.theme = selected;
  elementById('theme-toggle').setAttribute('aria-checked', String(selected === 'light'));
  if (persist) sendToApp('preference', { key: 'theme', value: selected });
  sendToApp('appearance', { theme: selected });
}
function showNotice(message) {
  clearTimeout(noticeTimer);
  elementById('notice').textContent = message;
  elementById('notice').hidden = false;
  noticeTimer = setTimeout(() => {
    elementById('notice').hidden = true;
  }, 3500);
}
function updateStatus() {
  const dirty = view.state.doc.toString() !== savedText;
  elementById('dirty-dot').hidden = !dirty;
  elementById('dirty-dot').title = recoveryOkay
    ? 'Unsaved changes · draft backed up locally'
    : 'Unsaved changes · recovery unavailable';
  elementById('document-name').title = currentPath || 'Unsaved document';
}
// Each native tab owns a separate editor state and undo history.
function createState(content) {
  return EditorState.create({
    doc: content,
    extensions: [
      markdown({ base: markdownLanguage, addKeymap: false }),
      history(),
      keymap.of([
        { key: 'Enter', run: insertNewlineContinueMarkupCommand({ nonTightLists: false }) },
        ...markdownKeymap.filter((binding) => binding.key !== 'Enter'),
        ...defaultKeymap,
        ...historyKeymap,
        indentWithTab,
      ]),
      drawSelection(),
      EditorView.lineWrapping,
      placeholder('start writing…'),
      EditorView.contentAttributes.of({
        'aria-label': 'Markdown editor',
        spellcheck: 'false',
        autocapitalize: 'off',
        autocorrect: 'off',
      }),
      livePreviewExtensions,
      EditorView.domEventHandlers({
        mousedown(event) {
          const link = event.target.closest('[data-link]');
          if (link && (event.metaKey || event.ctrlKey)) {
            event.preventDefault();
            openLink(view, link.dataset.link);
            return true;
          }
          return false;
        },
        drop(event) {
          if (event.dataTransfer?.files?.length) {
            event.preventDefault();
            showNotice('Use ⌘O to open a Markdown file');
            return true;
          }
          return false;
        },
      }),
      EditorView.updateListener.of((update) => {
        if (!update.docChanged) return;
        revision += 1;
        updateStatus();
        sendToApp('change', { content: update.state.doc.toString(), revision });
      }),
    ],
  });
}
const view = new EditorView({ state: createState(welcome), parent: elementById('editor') });
function loadDocument(doc) {
  const content = doc.content ?? welcome;
  savedText = doc.savedContent ?? content;
  currentPath = doc.path || '';
  revision = 0;
  view.setState(createState(content));
  view.contentDOM.blur();
  view.scrollDOM.scrollTop = 0;
  elementById('document-name').textContent = doc.name || 'untitled.md';
  document.title = `${doc.name || 'untitled.md'} — mdrift`;
  if (doc.preferences) setTheme(doc.preferences.theme || 'dark', false);
  updateStatus();
  if (doc.recovered) showNotice('Unsaved draft recovered');
}
function command(name) {
  if (name === 'theme')
    setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
  else if (name === 'undo') {
    undo(view);
    view.focus();
  } else if (name === 'redo') {
    redo(view);
    view.focus();
  } else if (name === 'selectAll') {
    selectAll(view);
    view.focus();
  } else if (name === 'focus') view.focus();
}
// The small API called by Document.swift through WKWebView.
window.mdrift = {
  loadDocument,
  command,
  toast: showNotice,
  setTheme: (value) => setTheme(value, false),
  didSave(doc) {
    savedText = doc.content;
    currentPath = doc.path || '';
    elementById('document-name').textContent = doc.name;
    document.title = `${doc.name} — mdrift`;
    updateStatus();
  },
  recoveryStatus(ok) {
    recoveryOkay = ok;
    updateStatus();
    if (!ok) showNotice('Draft backup unavailable. Save with ⌘S.');
  },
  // The plain Markdown model is also used by the local verification script.
  getText: () => view.state.doc.toString(),
};
elementById('theme-toggle').onclick = () => command('theme');
elementById('document-name').ondblclick = () => sendToApp('open');
document.querySelector('.titlebar').addEventListener('mousedown', (event) => {
  if (!event.target.closest('button')) view.contentDOM.blur();
});
loadDocument({ content: welcome, name: 'welcome.md' });
sendToApp('ready', { welcome });
