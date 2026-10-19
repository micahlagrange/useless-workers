// Plays the web build headless and takes screenshots, to see a change working.
//   node tools/drive.js steps.json outdir [--phone] [--url http://localhost:8000/morphis/]
// --phone is a 393x852 touch screen; without it, a 1280x720 desktop.
// Steps, in page pixels: {click:[x,y]} {tap:[x,y]} {drag:[x1,y1,x2,y2]}
// {move:[x,y]} {key:'Enter'} {type:'abc'} {wait:ms} {shot:'name'} {eval:'js'}
// Needs playwright (npm i playwright && npx playwright install chromium).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const args = process.argv.slice(2);
  const phone = args.includes('--phone');
  const urlAt = args.indexOf('--url');
  const url = urlAt >= 0 ? args[urlAt + 1] : 'http://localhost:8000/morphis/';
  const [stepsFile, out = '.'] = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--url');
  const steps = JSON.parse(fs.readFileSync(stepsFile, 'utf8'));
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const page = await browser.newPage(phone
    ? { viewport: { width: 393, height: 852 }, hasTouch: true, isMobile: true, deviceScaleFactor: 3 }
    : { viewport: { width: 1280, height: 720 } });
  const logs = [];
  page.on('console', m => { if (m.type() !== 'log' || /error/i.test(m.text())) logs.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => logs.push('PAGEERROR: ' + e.message));
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(6000);
  for (const s of steps) {
    if (s.click) {
      await page.mouse.move(s.click[0], s.click[1]);
      await page.waitForTimeout(60);
      await page.mouse.down(); await page.waitForTimeout(60); await page.mouse.up();
      await page.waitForTimeout(150);
    } else if (s.tap) {
      await page.touchscreen.tap(s.tap[0], s.tap[1]);
      await page.waitForTimeout(200);
    } else if (s.move) {
      await page.mouse.move(s.move[0], s.move[1], { steps: 3 });
      await page.waitForTimeout(100);
    } else if (s.drag) {
      await page.mouse.move(s.drag[0], s.drag[1]);
      await page.waitForTimeout(60);
      await page.mouse.down();
      await page.mouse.move(s.drag[2], s.drag[3], { steps: 8 });
      await page.waitForTimeout(60);
      await page.mouse.up();
      await page.waitForTimeout(150);
    } else if (s.type) {
      await page.keyboard.type(s.type);
      await page.waitForTimeout(200);
    } else if (s.eval) {
      console.log('EVAL', JSON.stringify(await page.evaluate(s.eval)));
    } else if (s.key) {
      await page.keyboard.press(s.key);
      await page.waitForTimeout(150);
    } else if (s.wait) {
      await page.waitForTimeout(s.wait);
    } else if (s.shot) {
      await page.screenshot({ path: path.join(out, s.shot + '.png') });
    }
  }
  console.log(logs.slice(0, 60).join('\n'));
  await browser.close();
})();
