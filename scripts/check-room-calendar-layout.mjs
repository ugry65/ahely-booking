// Offline viewport regression check of the real server-rendered calendar and CSS.
// First generate fixtures with ROOM_CALENDAR_PREVIEW=<dir> pnpm test.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { resolve, join } from 'node:path';
import { mkdir } from 'node:fs/promises';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.ROOM_LAYOUT_PLAYWRIGHT_MODULE || 'playwright');
const fixtureDirectory = process.argv[2];
assert.ok(fixtureDirectory, 'Provide the generated fixture directory');
const screenshotDirectory = process.env.ROOM_LAYOUT_SCREENSHOTS;
if (screenshotDirectory) await mkdir(screenshotDirectory, { recursive: true });
const browser = await chromium.launch({
  executablePath: process.env.ROOM_LAYOUT_BROWSER || undefined,
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
try {
  const page = await browser.newPage();
  for (const width of [1920, 1366, 1024, 768, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const view of ['month', 'list', 'bookings']) {
      await page.goto(pathToFileURL(resolve(fixtureDirectory, `${view}.html`)).href);
      const measured = await page.evaluate(() => ({
        viewport: window.innerWidth,
        bodyWidth: document.body.scrollWidth,
        cards: [...document.querySelectorAll('main > section > .card')].map(element => {
          const rect = element.getBoundingClientRect();
          return { width: rect.width, left: rect.left, right: rect.right };
        }),
      }));
      assert.ok(measured.cards.length >= 2, `${view}: expected filter and result cards`);
      assert.ok(measured.bodyWidth <= width + 1, `${view}/${width}: horizontal page overflow`);
      for (const card of measured.cards) {
        assert.ok(card.width >= width - 64, `${view}/${width}: card is too narrow (${card.width}px)`);
        assert.ok(card.left >= -1 && card.right <= width + 1, `${view}/${width}: card exceeds viewport`);
      }
      console.log(`${view} ${width}px: PASS, card ${measured.cards[0].width}px, no overflow`);
      if (screenshotDirectory) await page.screenshot({ path: join(screenshotDirectory, `${view}-${width}.png`), fullPage: true });
    }
  }
} finally {
  await browser.close();
}
