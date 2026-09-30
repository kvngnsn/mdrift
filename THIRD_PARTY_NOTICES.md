# Third-party notices

mdrift's own code is MIT licensed. Dependencies keep their respective licenses.

| Component                                                              | License                           | Included notice                  |
| ---------------------------------------------------------------------- | --------------------------------- | -------------------------------- |
| CodeMirror 6, Lezer, style-mod, w3c-keyname, crelt, find-cluster-break | MIT                               | `web/vendor/editor-LICENSES.txt` |
| Marked                                                                 | MIT and retained upstream notices | `web/vendor/marked-LICENSE`      |
| DOMPurify                                                              | Apache-2.0 OR MPL-2.0             | `web/vendor/dompurify-LICENSE`   |
| Source Code Pro                                                        | SIL Open Font License 1.1         | `web/fonts/LICENSE`              |

The build copies these notices into `build/web` and the app's `Contents/Resources` directory. Full dependency versions and integrity hashes are recorded in `package-lock.json`.

esbuild, Playwright, and Prettier are development tools. Their licenses are included in their npm packages; they are not shipped as part of the app.
