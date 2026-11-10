const { chromium } = require('playwright');
const [,, inJson, outPng] = process.argv;
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1400, height: 1000 }, locale: 'ja-JP', acceptDownloads: true });
  const p = await ctx.newPage(); p.setDefaultTimeout(10000);
  await p.goto('https://pokecardmaker.net/create', { waitUntil: 'networkidle', timeout: 60000 }).catch(()=>{});
  const [fc] = await Promise.all([p.waitForEvent('filechooser'), p.getByRole('button',{name:'Import',exact:true}).click()]);
  await fc.setFiles(inJson); await p.waitForTimeout(1500);
  const conf = p.getByRole('dialog').getByRole('button').filter({hasText:/import|confirm|ok|yes/i});
  if (await conf.count()) { console.log('confirm:', await conf.first().innerText()); await conf.first().click(); }
  await p.waitForTimeout(6000);
  p.on('download', async d => { await d.saveAs(outPng); console.log('dl'); });
  await p.getByRole('button',{name:'Download',exact:true}).click(); await p.waitForTimeout(1500);
  await p.getByRole('dialog').getByRole('button',{name:'Download'}).click(); await p.waitForTimeout(8000);
  await b.close();
})();
