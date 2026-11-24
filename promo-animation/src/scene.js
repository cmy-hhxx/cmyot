/**
 * MotionHarness Standard Scene Skeleton (1920x1080 @ 30fps).
 * Keep `prepareFrame(time)` as a pure deterministic function of absolute `time` (seconds).
 */

export default function ({ root, width, height }) {
  const stage = document.createElement('div');
  stage.style.cssText = `
    position: relative;
    width: ${width}px;
    height: ${height}px;
    overflow: hidden;
    background: #05060a;
    color: #f5f5f7;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", sans-serif;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    gap: 12px;
  `;

  const title = document.createElement('div');
  title.textContent = 'CoTEditor';
  title.style.cssText = 'font-size: 64px; font-weight: 700; letter-spacing: -0.02em;';

  const hint = document.createElement('div');
  hint.textContent = 'MotionHarness 动画工程框架已就绪';
  hint.style.cssText = 'font-size: 22px; color: rgba(245, 245, 247, 0.6);';

  stage.append(title, hint);
  root.append(stage);

  return {
    prepareFrame(time) {
      const fade = Math.min(1, Math.max(0, time / 0.5));
      stage.style.opacity = String(fade);
    },
    dispose() {
      stage.remove();
    },
  };
}
