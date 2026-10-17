// A small, usable clock appears before Flutter and its renderer are downloaded.
(() => {
  const doc = document;
  const message = doc.getElementById('loading-message');
  const retry = doc.getElementById('retry');
  const clock = doc.getElementById('loading-clock');
  let stopped = false;
  let slow = false;
  let phase = '正在下载应用资源';
  function paint() {
    const now = new Date();
    clock.textContent = [now.getHours(), now.getMinutes(), now.getSeconds()]
      .map(value => String(value).padStart(2, '0')).join(':');
  }
  function render() {
    message.textContent = slow
      ? `${phase}。网络较慢，可以先看时间，或重新加载。`
      : `${phase}…首次打开需要稍等片刻。`;
  }
  paint(); render();
  const tick = setInterval(paint, 1000);
  const watchdog = setTimeout(() => { if (!stopped) { slow = true; retry.hidden = false; render(); } }, 15000);
  window.shikeLoadingManaged = true;
  window.shikeLoader = {
    stage(value) { if (!stopped) { phase = value; render(); } },
    fail() {
      if (stopped) return;
      clearTimeout(watchdog);
      message.textContent = '完整界面加载未完成，基础时间仍可查看。请检查网络后重试。';
      retry.hidden = false;
    },
    ready() {
      if (stopped) return;
      stopped = true;
      clearInterval(tick); clearTimeout(watchdog);
      doc.getElementById('loading')?.remove();
      // Precache after the UI is usable, avoiding competition with startup.
      doc.dispatchEvent(new Event('shike-app-ready'));
    },
  };
  window.shikeLoadError = () => window.shikeLoader.fail();
})();
