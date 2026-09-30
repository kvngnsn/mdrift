const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const { pathToFileURL } = require('node:url');
const os = require('node:os');
const output = fs.mkdtempSync(path.join(os.tmpdir(), 'mdrift-editor-qa-'));

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1150, height: 820 } });
    page.setDefaultTimeout(8000);
    const errors = [],
      requests = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('request', (request) => {
      if (/^https?:/.test(request.url())) requests.push(request.url());
    });
    await page.addInitScript(() => {
      window.nativeMessages = [];
      window.webkit = {
        messageHandlers: { app: { postMessage: (m) => window.nativeMessages.push(m) } },
      };
    });
    await page.goto(pathToFileURL(path.join(__dirname, '../build/web/index.html')).href);
    await page.waitForFunction(() => !!window.mdrift);
    await page.evaluate(() => document.fonts.ready);
    const editor = page.getByRole('textbox', { name: 'Markdown editor' });
    const load = async (text) =>
      page.evaluate(
        (content) =>
          window.mdrift.loadDocument({ content, name: 'test.md', preferences: { theme: 'dark' } }),
        text,
      );
    const source = () => page.evaluate(() => window.mdrift.getText());
    const replace = async (text) => {
      await editor.click();
      await editor.press('Meta+a');
      await page.keyboard.insertText(text);
    };
    assert.equal(await page.locator('.cm-editor').count(), 1);
    assert.equal(
      await page.locator('#sidebar,#preview,.format-actions,.view-switch,.statusbar').count(),
      0,
    );
    assert.equal(await page.locator('button').count(), 1);
    assert.equal(await page.locator('.md-h1').innerText(), 'mdrift');
    assert.equal(await page.title(), 'welcome.md — mdrift');
    assert.equal(await page.evaluate(() => document.fonts.check('14px "Source Code Pro"')), true);
    assert.equal(
      await page.locator('body').evaluate((e) => getComputedStyle(e).backgroundColor),
      'rgb(8, 8, 8)',
    );
    await page.screenshot({ path: path.join(output, 'dark.png') });
    if (process.env.MDRIFT_SCREENSHOT) {
      await page.screenshot({ path: process.env.MDRIFT_SCREENSHOT });
    }
    await page.getByRole('switch', { name: 'Light mode' }).click();
    assert.equal(
      await page.locator('body').evaluate((e) => getComputedStyle(e).backgroundColor),
      'rgb(247, 247, 245)',
    );
    await page.screenshot({ path: path.join(output, 'light.png') });

    const original =
      '# Heading\n\nA **bold** and *italic* and ~~gone~~ word with `code`.\n\nNext line.\n';
    await load(original);
    assert.equal(await page.locator('.md-h1').innerText(), 'Heading');
    assert.equal(await page.locator('.md-strong').innerText(), 'bold');
    assert.equal(await page.locator('.md-emphasis').innerText(), 'italic');
    assert.equal(await page.locator('.md-strike').innerText(), 'gone');
    assert.equal(await source(), original);
    await page.locator('.md-h1').click();
    assert.match(await page.locator('.md-h1').innerText(), /# Heading/);
    await page.locator('.cm-line').filter({ hasText: 'Next line.' }).click();
    assert.equal(await page.locator('.md-h1').innerText(), 'Heading');
    assert.equal(await source(), original);
    await replace('# Live heading\n\nNew **words**.');
    assert.equal(await page.locator('.md-h1').innerText(), 'Live heading');
    assert.match(await page.locator('.md-strong').innerText(), /words/);
    assert.equal(await source(), '# Live heading\n\nNew **words**.');
    assert.equal(await page.locator('#dirty-dot').isVisible(), true);
    await page.evaluate(() => window.mdrift.command('undo'));
    assert.equal(await source(), original);
    await page.evaluate(() => window.mdrift.command('redo'));
    assert.equal(await source(), '# Live heading\n\nNew **words**.');
    await page.evaluate(() =>
      window.mdrift.didSave({
        content: window.mdrift.getText(),
        name: 'saved.md',
        path: '/tmp/saved.md',
      }),
    );
    assert.equal(await page.locator('#dirty-dot').isVisible(), false);
    assert.equal(await page.title(), 'saved.md — mdrift');

    await load('- [ ] First\n\nA place to write.');
    await page.getByRole('checkbox', { name: 'Toggle task' }).check();
    assert.equal(await source(), '- [x] First\n\nA place to write.');
    await replace('- item');
    await editor.press('End');
    await editor.press('Enter');
    assert.equal(await source(), '- item\n- ');
    await editor.press('Enter');
    assert.equal(await source(), '- item\n');
    await replace('Résumé — 你好 🙂\n\nA second paragraph.');
    assert.equal(await source(), 'Résumé — 你好 🙂\n\nA second paragraph.');

    const blocks =
      '# Blocks\n\n| A | B |\n|---|---|\n| one | two |\n\n```js\nconst a = 1;\n```\n\nEnd.\n';
    await load(blocks);
    assert.equal(await page.locator('table').count(), 1);
    assert.equal(await page.locator('pre code').innerText(), 'const a = 1;\n');
    await page.locator('td').first().click();
    await page.waitForFunction(() => !document.querySelector('table'));
    assert.equal(await page.locator('table').count(), 0);
    assert.match(await editor.innerText(), /\| one \| two \|/);
    await page.locator('.cm-line').filter({ hasText: 'End.' }).click();
    await page.waitForFunction(() => !!document.querySelector('table'));
    assert.equal(await page.locator('table').count(), 1);
    await page.locator('pre').click();
    await page.waitForFunction(() => !document.querySelector('pre'));
    assert.equal(await page.locator('pre').count(), 0);
    assert.match(await editor.innerText(), /```js/);
    assert.equal(await source(), blocks);

    await load('# Destination\n\n[Jump](#destination)\n\n[Notes](other.md)\n\nEnd.');
    await page.locator('[data-link="#destination"]').click({ modifiers: ['Meta'] });
    await page.waitForFunction(() =>
      document.querySelector('.md-h1').textContent.includes('# Destination'),
    );
    assert.match(await page.locator('.md-h1').innerText(), /# Destination/);
    await page.locator('[data-link="other.md"]').click({ modifiers: ['Meta'] });
    assert.equal(await page.evaluate(() => window.nativeMessages.at(-1).action), 'openRelative');
    assert.equal(await page.evaluate(() => window.nativeMessages.at(-1).path), 'other.md');
    await load('| Link |\n|---|\n| [Site](https://example.com) |\n\nEnd.');
    await page.locator('td a').click({ modifiers: ['Meta'] });
    assert.equal(await page.evaluate(() => window.nativeMessages.at(-1).action), 'openLink');
    assert.equal(
      await page.evaluate(() => window.nativeMessages.at(-1).url),
      'https://example.com',
    );

    await load(
      '# Security\n\n<script>window.compromised=true</script>\n\n![remote](https://example.com/tracker.png)\n\n| A | B |\n|---|---|\n| <img src="https://example.com/pixel" onerror="window.compromised=true"> | <iframe src="https://example.com"></iframe> |\n\n[bad](javascript:alert(1))\n',
    );
    assert.equal(await page.locator('#editor script,#editor iframe,#editor [onerror]').count(), 0);
    assert.equal(await page.evaluate(() => !!window.compromised), false);
    assert.equal(requests.length, 0);
    assert.equal(await page.locator('img[src^="https:"]').count(), 0);
    assert.equal(await page.locator('a[href^="javascript:"]').count(), 0);

    await load(
      Array.from(
        { length: 200 },
        (_, i) => `## Section ${i}\n\nSome **bold** text for section ${i}.\n`,
      ).join('\n'),
    );
    await editor.click();
    await editor.press('Meta+End');
    await page.keyboard.insertText('\nlast line');
    assert((await source()).endsWith('\nlast line'));
    await page.evaluate(() => window.mdrift.command('selectAll'));
    await page.keyboard.insertText('Replacement for the entire document.');
    assert.equal(await source(), 'Replacement for the entire document.');
    await page.evaluate(() => window.mdrift.command('undo'));
    assert((await source()).includes('Section 199'));
    await page.setViewportSize({ width: 620, height: 500 });
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
      false,
    );
    assert.deepEqual(errors, []);
    console.log(
      'PASS: one live editor, active-line Markdown, lossless source, live typing, native undo/redo, task toggles, list continuation, Unicode, tables/code, save state, long-document selection, both themes, local fonts, sanitization, zero network requests.',
    );
  } finally {
    await browser.close();
    fs.rmSync(output, { recursive: true, force: true });
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
