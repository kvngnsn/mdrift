import { build } from 'esbuild';
import { mkdir, copyFile, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectDir = fileURLToPath(new URL('../', import.meta.url));
const webDir = path.join(projectDir, 'build/web');
const modulesDir = path.join(projectDir, 'node_modules');

async function copyDependency(source, destination) {
  await copyFile(path.join(modulesDir, source), path.join(webDir, destination));
}

// Keep generated bundles and vendored dependencies out of the source tree.
await mkdir(path.join(webDir, 'vendor'), { recursive: true });
await mkdir(path.join(webDir, 'fonts'), { recursive: true });
for (const name of ['index.html', 'style.css']) {
  await copyFile(path.join(projectDir, 'src/web', name), path.join(webDir, name));
}
await build({
  entryPoints: [path.join(projectDir, 'src/editor.js')],
  bundle: true,
  minify: true,
  target: 'safari16',
  format: 'iife',
  outfile: path.join(webDir, 'app.js'),
  legalComments: 'eof',
});

await copyDependency('marked/lib/marked.umd.js', 'vendor/marked.js');
await copyDependency('marked/LICENSE', 'vendor/marked-LICENSE');
await copyDependency('dompurify/dist/purify.min.js', 'vendor/purify.js');
await copyDependency('dompurify/LICENSE', 'vendor/dompurify-LICENSE');
await copyDependency('dompurify/LICENSE-MPL', 'vendor/dompurify-LICENSE-MPL');
for (const style of ['normal', 'italic']) {
  await copyDependency(
    `@fontsource-variable/source-code-pro/files/source-code-pro-latin-wght-${style}.woff2`,
    `fonts/source-code-pro-${style}.woff2`,
  );
}
await copyDependency('@fontsource-variable/source-code-pro/LICENSE', 'fonts/LICENSE');

const editorPackages = [
  '@codemirror/state',
  '@codemirror/view',
  '@codemirror/commands',
  '@codemirror/language',
  '@codemirror/lang-markdown',
  '@codemirror/lang-html',
  '@codemirror/lang-css',
  '@codemirror/lang-javascript',
  '@codemirror/autocomplete',
  '@codemirror/lint',
  '@lezer/common',
  '@lezer/highlight',
  '@lezer/markdown',
  '@lezer/lr',
  '@lezer/html',
  '@lezer/css',
  '@lezer/javascript',
  '@marijn/find-cluster-break',
  'style-mod',
  'w3c-keyname',
  'crelt',
];
const licenses = [];
for (const name of editorPackages) {
  const directory = path.join(modulesDir, name);
  const metadata = JSON.parse(await readFile(path.join(directory, 'package.json'), 'utf8'));
  const license = await readFile(path.join(directory, 'LICENSE'), 'utf8');
  licenses.push(`${name} ${metadata.version}\n${license}`);
}
await writeFile(path.join(webDir, 'vendor/editor-LICENSES.txt'), licenses.join('\n\n---\n\n'));
console.log('Built the offline editor in build/web.');
