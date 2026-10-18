{{flutter_js}}
{{flutter_build_config}}

// Custom startup callbacks must explicitly forward the engine configuration.
const engineConfig = {
  renderer: 'canvaskit',
  canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
  hostElement: document.getElementById('app'),
};

_flutter.loader.load({
  config: engineConfig,
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      window.shikeLoader?.stage('正在初始化显示引擎');
      const runner = await engineInitializer.initializeEngine(engineConfig);
      window.shikeLoader?.stage('正在打开完整界面');
      await runner.runApp();
      if (window.shikeLoader) window.shikeLoader.ready();
      else {
        document.getElementById('loading')?.remove();
        document.dispatchEvent(new Event('shike-app-ready'));
      }
    } catch (error) {
      console.error('此刻启动失败', error);
      window.shikeLoadError();
    }
  },
}).catch(window.shikeLoadError);
