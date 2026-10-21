// Private data worker in WKWebView. Flutter renders every visible screen.
(() => {
  'use strict';
  const post = value => window.webkit.messageHandlers.shike.postMessage(JSON.stringify(value));
  const storage = new Map(Object.entries(globalThis.__shikeStorage || {}));
  delete globalThis.__shikeStorage;
  let visible = true;
  Object.defineProperty(document, 'hidden', { get: () => !visible });
  Object.defineProperty(document, 'visibilityState', { get: () => visible ? 'visible' : 'hidden' });
  Object.defineProperty(window, 'localStorage', { value: Object.freeze({
    getItem(key) { return storage.get(String(key)) ?? null; },
    setItem(key, value) {
      key = String(key); value = String(value);
      if (!key.startsWith('shike.') || value.length > 8000000) throw new Error('Invalid storage entry');
      storage.set(key, value); post({type:'storage',key,value});
    },
    removeItem(key) { key = String(key); storage.delete(key); post({type:'storage',key,value:null}); },
  }) });
  window.open = raw => { post({type:'openUrl',url:String(raw)}); return null; };
  const streams = new Map();
  const emit = (token, value) => post({type:'event',token,value:JSON.parse(value)});
  function cancel(token) {
    const entry = streams.get(token);
    if (!entry) return;
    streams.delete(token);
    if (entry.kind === 'crypto') timeNestDashboard.unsubscribeCrypto(entry.id);
    else if (entry.kind === 'rules') timeNestDashboard.unsubscribeCryptoRules(entry.id);
    else timeNestNetwork.cancel(entry.id);
  }
  const methods = {
    request: args => timeNestDashboard.request(args.module, JSON.stringify(args.args), args.refresh),
    subscribe(args) {
      cancel(args.token);
      const receive = raw => emit(args.token, raw);
      const id = args.kind === 'crypto' ? timeNestDashboard.subscribeCrypto(JSON.stringify(args.args), receive)
        : args.kind === 'rules' ? timeNestDashboard.subscribeCryptoRules(receive)
        : args.kind === 'network' ? timeNestNetwork.start(args.args.kind, JSON.stringify(args.args.args), receive)
        : null;
      if (id === null) throw new Error('Unsupported stream');
      streams.set(args.token,{kind:args.kind,id});
      return true;
    },
    cancel: args => cancel(args.token),
    resetBook: args => {
      const entry = streams.get(args.token);
      return entry?.kind === 'crypto' ? timeNestDashboard.resetCryptoBook(entry.id) : null;
    },
    cancelRequests: args => timeNestDashboard.cancelCryptoRequests(args.symbol),
    environment: () => timeNestNetwork.environment(),
    clearHistory: () => timeNestNetwork.clearHistory(),
    storageSet(args) { args.value === null ? storage.delete(args.key) : storage.set(args.key,args.value); },
    visibility(args) {
      const changed = visible !== args.visible;
      visible = args.visible;
      if (changed || args.resume) document.dispatchEvent(new Event('visibilitychange'));
    },
    shutdown() { for (const token of streams.keys()) cancel(token); },
  };
  globalThis.timeNestMac = Object.freeze({
    async call(id, method, args) {
      try {
        if (!Object.hasOwn(methods,method)) throw new Error('Unsupported method');
        const value = await methods[method](args);
        post({type:'reply',id,value:value ?? null});
      } catch (error) { post({type:'reply',id,error:String(error.message || error).slice(0,600)}); }
    },
  });
})();
