// stills.mjs — 3 视口截图 + 两帧对比 + console error 采集
//
// 用法: node stills.mjs <url> [outDir]
// 例:   node stills.mjs http://localhost:5173 docs/handoff/hero-motion/stills
//
// 依赖: playwright（本仓库或全局能 resolve 到即 可）
// 约定: 页面支持 ?still=<ms> 参数（见 still-pause.js），能把 CSS 动画暂停在指定时刻。
//       不支持时两帧可能完全相同，会被判为「疑未在动」并失败。
//
// 退出码: 0 通过 / 1 有 console error、页面报错，或主视效两帧完全相同（疑未在动）

import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

const [, , rawUrl, outDirArg] = process.argv;
if (!rawUrl) {
  console.error('用法: node stills.mjs <url> [outDir]');
  process.exit(2);
}
const outDir = outDirArg || 'stills';
const require = createRequire(import.meta.url);

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch {
  console.error('✗ 找不到 playwright。安装: pnpm add -D playwright && npx playwright install chromium');
  process.exit(2);
}

const viewports = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'tablet', width: 834, height: 1112 },
  { name: 'mobile', width: 390, height: 844 },
];
const frames = [0, 800]; // ms
const hash = (buf) => createHash('sha256').update(buf).digest('hex').slice(0, 16);

const withParam = (url, k, v) => {
  const u = new URL(url);
  u.searchParams.set(k, String(v));
  return u.toString();
};

await mkdir(outDir, { recursive: true });

const browser = await chromium.launch();
const problems = [];
let motionConfirmed = 0;

for (const vp of viewports) {
  const ctx = await browser.newContext({
    viewport: { width: vp.width, height: vp.height },
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));

  const hashes = [];
  for (const t of frames) {
    await page.goto(withParam(rawUrl, 'still', t), { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    const buf = await page.screenshot({ animations: 'allow', fullPage: false });
    const file = path.join(outDir, `${vp.name}-${t}ms.png`);
    await writeFile(file, buf);
    hashes.push(hash(buf));
  }

  // prefers-reduced-motion: 页面必须仍可用（截图存在即可，人工看）
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(withParam(rawUrl, 'still', '0'), { waitUntil: 'networkidle' });
  await page.waitForTimeout(300);
  await writeFile(
    path.join(outDir, `${vp.name}-reduced.png`),
    await page.screenshot({ animations: 'allow' }),
  );

  if (hashes[0] === hashes[1]) {
    problems.push(`[${vp.name}] 两帧截图完全相同（${hashes[0]}）→ 主视效可能没在动，或页面不支持 ?still= 参数`);
  } else {
    motionConfirmed++;
  }
  if (errors.length) problems.push(`[${vp.name}] 控制台报错:\n    ` + errors.slice(0, 5).join('\n    '));

  await ctx.close();
}

await browser.close();

console.log(`截图输出: ${outDir}/`);
console.log(`两帧有差异的视口: ${motionConfirmed}/${viewports.length}`);
if (problems.length) {
  console.error('\n✗ 问题:');
  for (const p of problems) console.error('  ' + p);
  process.exit(1);
}
console.log('\n✓ 截图门通过');
