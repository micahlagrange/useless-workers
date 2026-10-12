const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  page.on('console', m => logs.push(m.type() + ': ' + m.text()));
  page.on('pageerror', e => logs.push('PAGEERROR: ' + e.message));
  await page.goto('http://localhost:8000/morphis/', { waitUntil: 'load' });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: process.argv[2] || 'title.png' });
  console.log(logs.slice(0, 15).join('\n'));
  await browser.close();
})();
