# mdrift

A small, offline Markdown reader and editor for macOS. Read and edit in one place, with tabs, multiple windows, and light or dark mode.

## Install

**Open `mdrift.dmg` in this folder**, then drag **mdrift.app** into **Applications**. Requires macOS 13 or later.

The disk image also includes **New Markdown File.workflow**. Double-click it to add **New Markdown File** to Finder's right-click menu for selected files and folders.

Upgrading from the old **Markdown** app? Quit it first. mdrift copies its drafts and preferences on first launch; the old app and its backups remain.

Local builds are ad-hoc signed. Downloaded builds may need approval in **System Settings → Privacy & Security**.

## What's here

```text
mdrift.dmg   Installer — open this
README.md    This guide
LICENSE      MIT license
code/        Source, build tools, and tests
```

## Use

- **⌘O** opens files. **⌘S** saves. **⌘⇧S** saves a copy.
- **⌘T** or **⌘N** creates a tab. **⌘⇧N** creates a window.
- **⌘W** closes a tab. **⌘⇧W** closes its window.
- Click a passage to edit its Markdown. Click away to render it.
- Click checkboxes to update tasks; **⌘-click** links to follow them.
- The **Window** menu moves tabs between windows or merges windows.

Each tab has its own edits and undo history. Unsaved drafts recover after an interrupted session. Files change only when you save; external edits trigger a warning before overwriting.

Supports UTF-8 files up to 10 MB. Images inside the document's folder work; remote images stay placeholders.

## Working on the code

Requires macOS, Xcode Command Line Tools, Node.js 22+, and Python 3. No AI tools are needed.

```sh
cd code
npm ci --ignore-scripts
npm run package
```

This creates **`mdrift.dmg` in the main folder**. Generated app files stay in `code/build/`. Building does not install anything. Builds target the current Mac's architecture; set `MDRIFT_ARCH=arm64` or `MDRIFT_ARCH=x86_64` to choose another.

| Inside `code/`   | Purpose                                                              |
| ---------------- | -------------------------------------------------------------------- |
| `src/*.swift`    | Native windows, menus, files, and recovery; start with `main.swift`  |
| `src/editor.js`  | Editor controls and document state                                   |
| `src/preview.js` | Markdown rendering; `links.js` and `native.js` connect it to the app |
| `src/web/`       | Page layout and styling                                              |
| `scripts/`       | Builds the app, icon, Finder action, and installer                   |
| `tests/`         | Editor, native app, and Finder checks                                |
| `assets/`        | Icon and screenshot for the project                                  |

To test, run `npx playwright install chromium`, then `npm test` and `npm run test:native`. Native checks use temporary files and separate preferences. GitHub CI runs these checks too.

Use `npm run format` for JavaScript/docs and `npm run format:swift` for Swift. Keep names clear and functions focused. Rendering must preserve the original Markdown text.

[MIT license](LICENSE) · [Dependency notices](code/THIRD_PARTY_NOTICES.md)
