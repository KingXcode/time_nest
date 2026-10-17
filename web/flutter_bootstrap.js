{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    renderer: 'canvaskit',
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    hostElement: document.getElementById('app'),
  },
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      window.shikeLoader?.stage('正在初始化显示引擎');
      const runner = await engineInitializer.initializeEngine();
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
