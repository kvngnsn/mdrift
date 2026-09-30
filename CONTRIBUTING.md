# Contributing

mdrift uses plain Swift/AppKit for windows and files, plus a small CodeMirror editor in a bundled WebKit view. No backend or application framework is required.

## Start here

| File                    | Responsibility                                                     |
| ----------------------- | ------------------------------------------------------------------ |
| `src/main.swift`        | Starts the native app or its test runner                           |
| `src/App.swift`         | App lifecycle, opening files, and tab/window coordination          |
| `src/Menus.swift`       | Native menus and keyboard shortcuts                                |
| `src/Document.swift`    | One document's editor, state, native messages, and recovery backup |
| `src/FileAccess.swift`  | Open/save dialogs, UTF-8 and line endings, conflict prompts        |
| `src/LocalImages.swift` | Reads permitted images from the document's directory               |
| `src/Migration.swift`   | Copies drafts and preferences from the old app once                |
| `src/editor.js`         | CodeMirror setup, document state, theme, and editor commands       |
| `src/preview.js`        | Markdown decorations and widgets; never changes source text        |
| `src/links.js`          | Heading navigation and document/external links                     |
| `src/native.js`         | Sends messages from JavaScript to the native app                   |
| `src/web/`              | HTML and readable CSS                                              |
| `src/new-file.zsh`      | Creates a new Markdown file for the Finder action                  |
| `scripts/`              | Build, packaging, icon generation, and native test entry point     |
| `tests/`                | Browser, native, and Finder regression tests                       |

## How edits reach disk

1. Each document owns one `WKWebView` and one `NSWindow`. AppKit groups windows into tabs.
2. CodeMirror sends an `app` message after each edit. `Document.swift` updates that document's in-memory text and schedules its backup.
3. Native commands call the small `window.mdrift` API in `editor.js`.
4. Save writes the current document atomically. Rendering never rewrites the Markdown source.

There is no shared editor state between tabs. A theme change is the only preference broadcast across open documents.

## Local workflow

```sh
npm ci --ignore-scripts
npx playwright install chromium
npm run build
npm test
npm run test:native
```

`npm test` builds the editor and checks reading/editing, undo/redo, lists, tasks, tables, code, Unicode, themes, image/link safety, and the Finder command. `npm run test:native` checks file handling, independent tabs/windows, save and close prompts, recovery, and migration using a separate QA app. Native test windows appear briefly; they never load your real drafts.

The GitHub workflow runs the build and tests on macOS. CI results become available after the repository is pushed.

## Style

Prefer descriptive names, ordinary control flow, and small functions with one job. Comment decisions that are not obvious from the code. Keep format changes separate from behavior changes when practical.

```sh
npm run format
npm run format:swift
npm run format:check
npm run format:swift:check
```

Swift formatting uses `xcrun swift-format` from a recent Xcode toolchain. Formatting the source is optional for building and running it.

Edit `src/`, not `build/`. The build copies dependencies and their licenses from the pinned npm lockfile. Generated JavaScript, fonts, app bundles, disk images, and test fixtures stay out of Git.

## Packaging

`npm run package` creates the app and Finder workflow, then writes `dist/mdrift.dmg`. The icon is generated from `scripts/make-icon.swift`. Its text and geometry are ordinary AppKit drawing code.

Local builds use an ad-hoc signature. A public notarized release would need a separate Apple Developer signing and notarization setup; this repository does not contain signing credentials or publish releases automatically.
