import { StateEffect, StateField } from '@codemirror/state';
import { EditorView, Decoration, WidgetType } from '@codemirror/view';
import { syntaxTree } from '@codemirror/language';
import { isNativeApp } from './native.js';
import { openLink } from './links.js';

// Widgets render Markdown without changing the underlying plain text.
class Bullet extends WidgetType {
  eq() {
    return true;
  }
  toDOM() {
    const el = document.createElement('span');
    el.className = 'md-bullet';
    el.textContent = '•';
    return el;
  }
  ignoreEvent() {
    return false;
  }
}
class Checkbox extends WidgetType {
  constructor(checked, from) {
    super();
    this.checked = checked;
    this.from = from;
  }
  eq(other) {
    return this.checked === other.checked && this.from === other.from;
  }
  toDOM(editor) {
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.className = 'md-checkbox';
    input.checked = this.checked;
    input.setAttribute('aria-label', 'Toggle task');
    input.addEventListener('mousedown', (event) => event.preventDefault());
    input.addEventListener('change', () =>
      editor.dispatch({
        changes: { from: this.from + 1, to: this.from + 2, insert: input.checked ? 'x' : ' ' },
        userEvent: 'input',
      }),
    );
    return input;
  }
  ignoreEvent() {
    return true;
  }
}
class Block extends WidgetType {
  constructor(source, from, kind) {
    super();
    this.source = source;
    this.from = from;
    this.kind = kind;
  }
  eq(other) {
    return this.source === other.source && this.from === other.from && this.kind === other.kind;
  }
  get estimatedHeight() {
    return this.kind === 'HorizontalRule' ? 42 : this.source.split('\n').length * 26 + 28;
  }
  toDOM(editor) {
    const el = document.createElement('div');
    el.className = 'md-block';
    el.setAttribute(
      'aria-label',
      this.kind === 'Table'
        ? 'Table. Click to edit Markdown.'
        : this.kind === 'HorizontalRule'
          ? 'Divider'
          : 'Code block. Click to edit.',
    );
    if (this.kind === 'HorizontalRule') {
      const rule = document.createElement('hr');
      rule.className = 'md-rule';
      el.append(rule);
    } else {
      el.append(
        DOMPurify.sanitize(marked.parse(this.source), {
          RETURN_DOM_FRAGMENT: true,
          ALLOWED_TAGS: [
            'pre',
            'code',
            'table',
            'thead',
            'tbody',
            'tr',
            'th',
            'td',
            'strong',
            'em',
            'del',
            'a',
            'br',
            'p',
          ],
          ALLOWED_ATTR: ['href', 'align'],
        }),
      );
    }
    el.addEventListener('mousedown', (event) => {
      if ((event.metaKey || event.ctrlKey) && event.target.closest('a')) {
        event.preventDefault();
        openLink(editor, event.target.closest('a').getAttribute('href') || '');
        return;
      }
      event.preventDefault();
      let offset = 0;
      if (this.kind === 'FencedCode') offset = this.source.indexOf('\n') + 1;
      if (this.kind === 'Table') {
        const row = event.target.closest('tr');
        if (row) {
          const rows = Array.from(el.querySelectorAll('tr'));
          const index = rows.indexOf(row);
          offset = this.source
            .split('\n')
            .slice(0, index === 0 ? 0 : index + 1)
            .reduce((sum, line) => sum + line.length + 1, 0);
        }
      }
      editor.dispatch({
        selection: { anchor: Math.min(this.from + offset, editor.state.doc.length) },
      });
      editor.focus();
    });
    return el;
  }
  ignoreEvent() {
    return true;
  }
}
class ImagePreview extends WidgetType {
  constructor(source, alt, from) {
    super();
    this.source = source;
    this.alt = alt;
    this.from = from;
  }
  eq(other) {
    return this.source === other.source && this.alt === other.alt && this.from === other.from;
  }
  toDOM(editor) {
    const el = document.createElement('span');
    el.className = 'md-image';
    const remote = /^(https?:)?\/\//i.test(this.source);
    const local = !/^(?:[a-z][a-z0-9+.-]*:|\/)/i.test(this.source);
    if (!remote && (local || /^data:image\/(png|jpeg|gif|webp);base64,/i.test(this.source))) {
      const img = document.createElement('img');
      img.alt = this.alt;
      img.src =
        local && isNativeApp
          ? `mdrift-asset://document/${this.source.replace(/^\.\//, '')}`
          : this.source;
      img.addEventListener('load', () => editor.requestMeasure());
      el.append(img);
    } else {
      const label = document.createElement('span');
      label.className = 'md-image-label';
      label.textContent = `[image: ${this.alt || 'image'}]`;
      el.append(label);
    }
    el.addEventListener('mousedown', (event) => {
      event.preventDefault();
      if ((event.metaKey || event.ctrlKey) && remote) {
        openLink(editor, this.source.startsWith('//') ? `https:${this.source}` : this.source);
        return;
      }
      editor.dispatch({ selection: { anchor: this.from } });
      editor.focus();
    });
    return el;
  }
  ignoreEvent() {
    return true;
  }
}

// Only the line being edited exposes Markdown punctuation.
const focusedEffect = StateEffect.define();
const focused = StateField.define({
  create: () => false,
  update(value, transaction) {
    for (const effect of transaction.effects) if (effect.is(focusedEffect)) value = effect.value;
    return value;
  },
});

function buildDecorations(state) {
  const ranges = [];
  const active = (from, to) =>
    state.field(focused) &&
    state.selection.ranges.some(
      (selection) =>
        from <= state.doc.lineAt(selection.to).to && to >= state.doc.lineAt(selection.from).from,
    );
  const mark = (from, to, className, attributes) => {
    if (from < to) ranges.push(Decoration.mark({ class: className, attributes }).range(from, to));
  };
  const hide = (from, to) => {
    if (from < to) ranges.push(Decoration.replace({}).range(from, to));
  };
  const line = (pos, className) =>
    ranges.push(Decoration.line({ class: className }).range(state.doc.lineAt(pos).from));
  const eachLine = (from, to, className) => {
    for (let current = state.doc.lineAt(from); current.from <= to;) {
      line(current.from, className);
      if (current.number >= state.doc.lines) break;
      current = state.doc.line(current.number + 1);
    }
  };
  syntaxTree(state).iterate({
    enter(ref) {
      const node = ref.node,
        name = node.name;
      const raw = () => state.doc.sliceString(node.from, node.to);
      if (['FencedCode', 'CodeBlock', 'Table', 'HorizontalRule'].includes(name)) {
        // Blocks inside list/quote containers retain source layout, which keeps nesting lossless.
        if (node.parent?.name === 'Document' && !active(node.from, node.to)) {
          ranges.push(
            Decoration.replace({ widget: new Block(raw(), node.from, name), block: true }).range(
              node.from,
              node.to,
            ),
          );
          return false;
        }
        eachLine(
          node.from,
          node.to,
          name === 'Table'
            ? 'md-table-source'
            : name === 'HorizontalRule'
              ? 'md-syntax'
              : 'md-code-source',
        );
        return false;
      }
      if (/^(ATX|Setext)Heading[1-6]$/.test(name)) line(node.from, `md-h${name.at(-1)}`);
      if (name === 'HeaderMark') {
        if (active(node.from, node.to)) mark(node.from, node.to, 'md-syntax');
        else {
          const end = state.doc.lineAt(node.to).to;
          const spaces = state.doc.sliceString(node.to, end).match(/^ +/)?.[0].length || 0;
          hide(node.from, node.to + spaces);
        }
      }
      if (name === 'StrongEmphasis') mark(node.from, node.to, 'md-strong');
      if (name === 'Emphasis') mark(node.from, node.to, 'md-emphasis');
      if (name === 'Strikethrough') mark(node.from, node.to, 'md-strike');
      if (name === 'InlineCode') mark(node.from, node.to, 'md-inline-code');
      if (['EmphasisMark', 'StrikethroughMark', 'CodeMark'].includes(name)) {
        if (active(node.from, node.to)) mark(node.from, node.to, 'md-syntax');
        else hide(node.from, node.to);
      }
      if (name === 'Blockquote') eachLine(node.from, node.to, 'md-quote');
      if (name === 'QuoteMark') {
        if (active(node.from, node.to)) mark(node.from, node.to, 'md-syntax');
        else
          hide(node.from, node.to + (state.doc.sliceString(node.to, node.to + 1) === ' ' ? 1 : 0));
      }
      if (name === 'ListMark') {
        if (active(node.from, node.to) || /^\d/.test(raw())) mark(node.from, node.to, 'md-syntax');
        else ranges.push(Decoration.replace({ widget: new Bullet() }).range(node.from, node.to));
      }
      if (name === 'TaskMarker') {
        if (active(node.from, node.to)) mark(node.from, node.to, 'md-syntax');
        else
          ranges.push(
            Decoration.replace({ widget: new Checkbox(/x/i.test(raw()), node.from) }).range(
              node.from,
              node.to,
            ),
          );
        if (/x/i.test(raw())) mark(node.to, node.parent.to, 'md-completed');
      }
      if (name === 'Link' || name === 'Image') {
        const url = node.getChild('URL');
        const marks = node.getChildren('LinkMark');
        if (!url || marks.length < 2) return;
        let href = state.doc.sliceString(url.from, url.to).replace(/^<|>$/g, '');
        href = href.replace(/\\([()])/g, '$1');
        const labelFrom = marks[0].to,
          labelTo = marks[1].from;
        if (name === 'Image') {
          if (!active(node.from, node.to)) {
            ranges.push(
              Decoration.replace({
                widget: new ImagePreview(
                  href,
                  state.doc.sliceString(labelFrom, labelTo),
                  node.from,
                ),
              }).range(node.from, node.to),
            );
            return false;
          }
          mark(node.from, node.to, 'md-syntax');
          return false;
        }
        mark(labelFrom, labelTo, 'md-link', { 'data-link': href, title: '⌘ click to open link' });
        if (active(node.from, node.to)) {
          mark(node.from, labelFrom, 'md-syntax');
          mark(labelTo, node.to, 'md-syntax');
        } else {
          hide(node.from, labelFrom);
          hide(labelTo, node.to);
        }
      }
      if (name === 'Autolink') {
        const text = raw();
        const bracketed = text.startsWith('<');
        const href = bracketed ? text.slice(1, -1) : text;
        const start = node.from + (bracketed ? 1 : 0),
          end = node.to - (bracketed ? 1 : 0);
        mark(start, end, 'md-link', { 'data-link': href, title: '⌘ click to open link' });
        if (bracketed && !active(node.from, node.to)) {
          hide(node.from, start);
          hide(end, node.to);
        }
      }
    },
  });
  return Decoration.set(ranges, true);
}

const livePreview = StateField.define({
  create: buildDecorations,
  update(value, transaction) {
    if (
      transaction.docChanged ||
      transaction.selection ||
      transaction.effects.some((effect) => effect.is(focusedEffect)) ||
      syntaxTree(transaction.state) !== syntaxTree(transaction.startState)
    )
      return buildDecorations(transaction.state);
    return value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

// Focus and selection determine which lines expose their Markdown syntax.
export const livePreviewExtensions = [
  focused,
  EditorView.focusChangeEffect.of((state, value) => focusedEffect.of(value)),
  livePreview,
];
