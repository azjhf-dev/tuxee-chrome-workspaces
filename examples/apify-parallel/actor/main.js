// Minimal Apify/Crawlee-style actor that attaches to its workspace's Chrome.
//
// cws provides (see `cws env NAME`):
//   CHROME_DEBUG_PORT      - CDP endpoint of THIS workspace's Chrome
//   CRAWLEE_STORAGE_DIR    - this workspace's private storage (datasets etc.)
//   APIFY_LOCAL_STORAGE_DIR- same, for the older Apify SDK
//   CWS_WORKSPACE          - workspace name
//
// Because each workspace has its own Chrome, port and storage dir, you can
// run this exact file in N workspaces at once and nothing collides.
//
// npm i puppeteer-core crawlee
const puppeteer = require('puppeteer-core');
const { Dataset } = require('crawlee');

const START_URL = process.env.START_URL || 'https://example.com';

(async () => {
  const port = process.env.CHROME_DEBUG_PORT;
  if (!port) throw new Error('CHROME_DEBUG_PORT not set - run via `cws apify NAME -- node main.js`');

  const browser = await puppeteer.connect({ browserURL: `http://127.0.0.1:${port}` });
  const page = await browser.newPage();

  console.log(`[${process.env.CWS_WORKSPACE}] visiting ${START_URL}`);
  await page.goto(START_URL, { waitUntil: 'domcontentloaded', timeout: 60_000 });

  const data = {
    workspace: process.env.CWS_WORKSPACE,
    url: START_URL,
    title: await page.title(),
    scrapedAt: new Date().toISOString(),
  };

  // Dataset writes into CRAWLEE_STORAGE_DIR, i.e. this workspace only.
  await Dataset.pushData(data);
  console.log(`[${process.env.CWS_WORKSPACE}] saved:`, data);

  await page.close();
  await browser.disconnect(); // disconnect, not close: cws owns the Chrome lifecycle
})().catch((err) => {
  console.error(`[${process.env.CWS_WORKSPACE}] failed:`, err);
  process.exit(1);
});
