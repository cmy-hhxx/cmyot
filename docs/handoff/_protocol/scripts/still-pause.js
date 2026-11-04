// still-pause.js — 让页面支持 ?still=<ms>，把动画定格在指定时刻，供截图对比
//
// 用途：接力协议要求"主视觉动效确实在播"可被机器验证。
//   同一页面在 ?still=0 和 ?still=800 两张截图的字节必须不同。
//
// 安装（三选一）：
//   1) 直接把这个文件放进 public/ 并在 <head> 末尾加 <script src="/still-pause.js" defer></script>
//   2) 把下面的 IIFE 粘进你的 dev 入口（仅 dev 环境）
//   3) 写成 vite 插件注入 —— 不推荐，够用就行
//
// 覆盖范围：CSS Animation / CSS Transition / Web Animations API。
// 不覆盖：requestAnimationFrame 驱动的 canvas、GSAP、Framer Motion 的 JS 时间轴。
//   这类项目请自己实现 window.__seek(ms)（把时间轴 time() 或 progress 设成指定值），
//   本脚本会在调用时优先使用它。

(() => {
  const params = new URLSearchParams(location.search);
  if (!params.has('still')) return;

  const t = Number(params.get('still')) || 0;

  const freeze = () => {
    // 项目自己实现的 seek 优先
    if (typeof window.__seek === 'function') {
      try { window.__seek(t); } catch (e) { console.warn('[still] __seek 失败', e); }
    }
    // CSS 动画 / 过渡 / WAAPI
    let n = 0;
    for (const a of document.getAnimations()) {
      try {
        a.pause();
        a.currentTime = t;
        n++;
      } catch { /* 某些动画不可 seek，忽略 */ }
    }
    document.documentElement.dataset.stillPaused = String(n);
  };

  const run = () => {
    freeze();
    // 部分动画在首帧后创建（例如 IntersectionObserver 触发），再补一次
    requestAnimationFrame(freeze);
    setTimeout(freeze, 300);
  };

  if (document.readyState === 'complete') run();
  else window.addEventListener('load', run, { once: true });

  console.debug(`[still] paused animations at ${t}ms`);
})();
