const { chromium } = require('playwright');
(async () => { const b = await chromium.launch();
for (const [n,w,h] of [['header',1400,700],['diagram',1400,470]]) { const p = await b.newPage({viewport:{width:w,height:h},deviceScaleFactor:2});
await p.goto('file://'+__dirname+'/'+n+'.html'); await p.screenshot({path:__dirname+'/../'+n+'.png'}); await p.close(); }
await b.close(); })();
