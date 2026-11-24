{{flutter_js}}
{{flutter_build_config}}

(async function startOnepoint() {
  const version = '20261124-unpaid-lessons-v1';
  const legacyWorker = worker => /\/flutter_service_worker\.js(?:\?|$)/.test(worker?.scriptURL || '');
  async function cleanLegacyCache() {
    let controlled = false;
    try {
      const workers = navigator.serviceWorker;
      controlled = legacyWorker(workers?.controller);
      if (workers) {
        const registrations = await workers.getRegistrations();
        await Promise.all(registrations.filter(registration =>
          legacyWorker(registration.active || registration.waiting || registration.installing))
          .map(registration => registration.unregister()));
      }
    } catch (_) { /* Some in-app browsers deny service-worker access. */ }
    try {
      const cache = window.caches;
      if (cache) {
        const names = await cache.keys();
        await Promise.all(names.filter(name => name.startsWith('flutter-')).map(name => cache.delete(name)));
      }
    } catch (_) { /* Cache access must never prevent application startup. */ }
    return controlled;
  }
  let cleanupTimer;
  const controlled = await Promise.race([
    cleanLegacyCache(),
    new Promise(resolve => { cleanupTimer = setTimeout(() => resolve(false), 1500); }),
  ]);
  clearTimeout(cleanupTimer);
  const url = new URL(window.location.href);
  if (controlled && url.searchParams.get('appVersion') !== version) {
    url.searchParams.set('appVersion', version);
    window.location.replace(url.toString());
    return;
  }
  const inApp = /KAKAOTALK|KAKAOSTORY|Instagram|FBAN|FBAV|NAVER|Line\//i.test(navigator.userAgent);
  let webGL = false;
  try {
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('webgl2') || canvas.getContext('webgl');
    webGL = !!context;
    context?.getExtension('WEBGL_lose_context')?.loseContext();
  } catch (_) { /* CanvasKit can use its CPU renderer instead. */ }
  const config = {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).toString(),
    canvasKitVariant: 'full',
    canvasKitForceCpuOnly: inApp || !webGL || url.searchParams.get('render') === 'compat',
  };
  try {
    await _flutter.loader.load({
      config,
      onEntrypointLoaded: async function(initializer) {
        try {
          const runner = await initializer.initializeEngine(config);
          await runner.runApp();
        } catch (error) {
          console.error('ONEPOINT startup failed', error);
          window.onepointStartup?.fail();
        }
      },
    });
  } catch (error) {
    console.error('ONEPOINT loader failed', error);
    window.onepointStartup?.fail();
  }
})();
