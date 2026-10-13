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
  const context = await browser.newContext({ locale: "hu-HU" });
  const page = await context.newPage();
  for (const width of [1920, 1366, 1280, 1024, 768, 390, 320]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const view of ['month', 'list', 'bookings']) {
     for (const gutter of ['auto', 'stable']) {
      await page.goto(pathToFileURL(resolve(fixtureDirectory, `${view}.html`)).href);
      if (gutter === "stable") await page.addStyleTag({ content: "html { scrollbar-gutter: stable; } body { overflow-y: scroll; }" });
      const measured = await page.evaluate(() => ({
        viewport: window.innerWidth,
        bodyWidth: document.body.scrollWidth,
        controls: [...document.querySelectorAll('.filters input:not([type="hidden"]), .filters select, .filters button')].map(element => {
          const rect = element.getBoundingClientRect();
          const parent = element.closest('label') || element.closest('form');
          const bounds = parent.getBoundingClientRect();
          return { name: element.getAttribute('name') || element.textContent, left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, parentLeft: bounds.left, parentRight: bounds.right };
        }),
        dayLinks: [...document.querySelectorAll('a.day')].map(element => element.getAttribute('href')),
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
      assert.ok(measured.controls.length >= 5, `${view}: expected search controls`);
      for (const [index, control] of measured.controls.entries()) {
        assert.ok(control.left >= control.parentLeft - 1 && control.right <= control.parentRight + 1, `${view}/${width}/${gutter}: ${control.name} exceeds its field`);
        for (const other of measured.controls.slice(index + 1)) {
          const x = Math.min(control.right, other.right) - Math.max(control.left, other.left);
          const y = Math.min(control.bottom, other.bottom) - Math.max(control.top, other.top);
          assert.ok(x <= .5 || y <= .5, `${view}/${width}/${gutter}: ${control.name} overlaps ${other.name}`);
        }
      }
      if (view === 'month') {
        assert.equal(measured.dayLinks.length, 31);
        for (const href of measured.dayLinks) {
          const url = new URL(href, 'https://calendar-fixture.invalid');
          assert.equal(url.pathname, '/foglalasok');
          assert.ok(!url.searchParams.has('view'), 'A day must open the daily calendar directly');
          assert.match(url.searchParams.get('datum'), /^2026-10-\d{2}$/);
          assert.ok(url.searchParams.get('room'), 'Keep the chosen room in the daily handoff');
        }
      }
      console.log(`${view} ${width}px/${gutter}: PASS, card ${measured.cards[0].width}px, no overlap/overflow`);
      if (screenshotDirectory && gutter === 'stable' && [1920,1366,390].includes(width)) await page.screenshot({ path: join(screenshotDirectory, `${view}-${width}.png`), fullPage: true });
     }
    }
  }
} finally {
  await browser.close();
}
