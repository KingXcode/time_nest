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
      const runner = await engineInitializer.initializeEngine();
      await runner.runApp();
      document.getElementById('loading')?.remove();
    } catch (error) {
      console.error('此刻启动失败', error);
      window.shikeLoadError();
    }
  },
}).catch(window.shikeLoadError);
