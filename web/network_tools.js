(() => {
  'use strict';

  // Public documented endpoints; no credentials, proxy, telemetry or auto-run.
  // https://github.com/cloudflare/speedtest
  // https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/
  const DOWN = 'https://speed.cloudflare.com/__down';
  const UP = 'https://speed.cloudflare.com/__up';
  const DNS = 'https://cloudflare-dns.com/dns-query';
  const PROBE = 'time-nest-network-probe-v1\n';
  const TYPES = { A: 1, NS: 2, CNAME: 5, MX: 15, TXT: 16, AAAA: 28 };
  const TYPE_NAMES = { ...Object.fromEntries(Object.entries(TYPES).map(([k, v]) => [v, k])), 6: 'SOA' };
  const LINKS = new Set([
    'https://github.com/cloudflare/speedtest',
    'https://www.cloudflare.com/privacypolicy/',
    'https://www.cloudflare.com/website-terms/',
    'https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/',
  ]);
  const HISTORY_KEY = 'shike.network.history.v1';
  let storageAvailable = true;
  const runs = new Map();
  let serial = 0;
  class TestError extends Error {
    constructor(message, fatal = false) { super(message); this.fatal = fatal; }
  }
  const now = () => performance.now();
  const stamp = () => new Date().toISOString();
  const finite = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
  function environment() {
    const connection = globalThis.navigator?.connection;
    return JSON.stringify({
      online: typeof navigator?.onLine === 'boolean' ? navigator.onLine : null,
      secure: typeof globalThis.isSecureContext === 'boolean' ? isSecureContext : null,
      effectiveType: ['slow-2g', '2g', '3g', '4g'].includes(connection?.effectiveType) ? connection.effectiveType : null,
      estimatedDownlinkMbps: finite(connection?.downlink),
      estimatedRttMs: finite(connection?.rtt),
      saveData: typeof connection?.saveData === 'boolean' ? connection.saveData : null,
    });
  }
  function cleanRecord(value) {
    if (!value || !['speed', 'latency'].includes(value.kind)
        || !['complete', 'error', 'cancelled'].includes(value.status)
        || typeof value.completedAt !== 'string' || value.completedAt.length > 40
        || !Number.isFinite(Date.parse(value.completedAt))) return null;
    const record = { kind: value.kind, status: value.status,
      provider: value.kind === 'latency' ? '本站 HTTPS' : 'Cloudflare', completedAt: value.completedAt };
    for (const key of ['latencyMs', 'jitterMs', 'downloadMbps', 'uploadMbps']) {
      record[key] = value.status === 'complete' ? finite(value[key]) : null;
      if (value.kind === 'latency' && (key === 'downloadMbps' || key === 'uploadMbps')) record[key] = null;
    }
    return record;
  }
  function historyItems() {
    const raw = globalThis.localStorage.getItem(HISTORY_KEY);
    if (!raw || raw.length > 32768) return [];
    let values;
    try { values = JSON.parse(raw); } catch (_) { return []; }
    if (!Array.isArray(values)) return [];
    return values.slice(0, 100).map(cleanRecord).filter(Boolean).slice(0, 20);
  }
  function history() {
    try { return JSON.stringify({ available: storageAvailable, items: historyItems() }); }
    catch (_) { return JSON.stringify({ available: false, items: [] }); }
  }
  function remember(run, status) {
    if (run.kind === 'dns') return;
    const record = cleanRecord({ ...run.result, kind: run.kind, status });
    if (!record) return;
    try {
      globalThis.localStorage.setItem(HISTORY_KEY, JSON.stringify([record, ...historyItems()].slice(0, 20)));
      storageAvailable = true;
    } catch (_) { storageAvailable = false; }
  }
  function clearHistory() {
    try { globalThis.localStorage.removeItem(HISTORY_KEY); storageAvailable = true; return true; }
    catch (_) { storageAvailable = false; return false; }
  }
  function emit(run, status = 'running', message) {
    if (run.finished) return;
    const terminal = status !== 'running';
    if (terminal) {
      run.result.completedAt = stamp();
      remember(run, status);
      clearTimeout(run.deadline);
      run.finished = true;
      runs.delete(run.id);
    }
    try {
      run.callback(JSON.stringify({
        kind: run.kind, status, stage: run.stage, progress: run.progress,
        ...(message ? { message } : {}), result: run.result,
      }));
    } catch (_) {
      // A broken/disposed listener must not leave transfers running unseen.
      if (!terminal) cancel(run.id);
    }
  }
  function cancel(id, message = '已取消。未完成的数据不作为测速结果。') {
    const run = runs.get(id);
    if (!run || run.finished) return;
    run.cancelled = true;
    for (const controller of run.controllers) controller.abort();
    emit(run, 'cancelled', message);
  }
  function check(run) {
    if (run.cancelled || run.finished) throw new TestError('测试已停止。', true);
  }
  async function request(run, url, { method = 'GET', body, expectedBytes, maxBytes = 8192, headers } = {}) {
    check(run);
    const controller = new AbortController();
    run.controllers.add(controller);
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; controller.abort(); }, 8000);
    const started = now();
    try {
      const response = await fetch(url, {
        method, body, headers, signal: controller.signal,
        mode: 'cors', cache: 'no-store', credentials: 'omit',
        referrerPolicy: 'no-referrer', redirect: 'error',
      });
      check(run);
      if (!response.ok || response.type === 'opaque') {
        throw new TestError(`服务返回 HTTP ${response.status}，本次无法测量；请稍后手动重试。`, true);
      }
      if (/text\/html/i.test(response.headers.get('content-type') || '')) {
        throw new TestError('服务返回网页而非测量数据，本次无法测量。', true);
      }
      // Count actual streamed bytes; never trust requested length or Content-Length.
      // Stream cancellation bounds unexpected/oversize responses on the client.
      const chunks = [];
      let received = 0;
      if (!response.body?.getReader) throw new TestError('浏览器不支持流式网络测量，请使用较新的浏览器。', true);
      const reader = response.body.getReader();
      try {
        while (true) {
          check(run);
          const { value, done } = await reader.read();
          if (done) break;
          check(run);
          received += value.byteLength;
          if (received > maxBytes) {
            controller.abort();
            throw new TestError('响应超过允许大小，已停止请求。', true);
          }
          chunks.push(value);
        }
      } finally {
        if (run.cancelled || controller.signal.aborted) await reader.cancel().catch(() => {});
        reader.releaseLock();
      }
      check(run);
      if (expectedBytes != null && received !== expectedBytes) {
        throw new TestError('实际下载大小与请求不符，本次不计算速度。', true);
      }
      const bytes = new Uint8Array(received);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      return { bytes, elapsed: now() - started };
    } catch (error) {
      if (run.cancelled || run.finished) throw error;
      if (error instanceof TestError) throw error;
      if (timedOut) throw new TestError('本次请求超时，可能是网络较慢或服务不可达。');
      throw new TestError('本次无法测量，可能是网络、跨域或服务限制；不代表目标服务宕机。');
    } finally {
      // Fetch resolves at headers: HTTP/HTML rejection must also stop its body.
      // Aborting a fully consumed successful response is harmless.
      controller.abort();
      clearTimeout(timeout);
      run.controllers.delete(controller);
    }
  }
  function probeUrl(run) {
    if (run.kind === 'speed') {
      return `${DOWN}?bytes=0&tn=${encodeURIComponent(run.id)}-${run.result.attempted}`;
    }
    const url = new URL('network-probe.txt', document.baseURI);
    if (url.origin !== location.origin || !['http:', 'https:'].includes(url.protocol)) {
      throw new TestError('本站探针地址无效，无法测量。', true);
    }
    url.searchParams.set('tn', `${run.id}-${run.result.attempted}`);
    return url.href;
  }
  async function latency(run, count) {
    const samples = run.result.samples;
    // Exclude one warm-up request (connection setup) from the sample statistics.
    run.stage = 'warmup';
    emit(run);
    const warmup = await request(run, probeUrl(run), { expectedBytes: run.kind === 'speed' ? 0 : PROBE.length, maxBytes: 1024 });
    if (run.kind === 'latency' && new TextDecoder().decode(warmup.bytes) !== PROBE) {
      throw new TestError('本站探针内容异常，无法排除缓存或错误页面。', true);
    }
    run.stage = 'latency';
    for (let i = 0; i < count; i++) {
      check(run);
      run.result.attempted++;
      try {
        const data = await request(run, probeUrl(run), { expectedBytes: run.kind === 'speed' ? 0 : PROBE.length, maxBytes: 1024 });
        if (run.kind === 'latency' && new TextDecoder().decode(data.bytes) !== PROBE) {
          throw new TestError('本站探针内容异常，本次无法测量。', true);
        }
        samples.push(data.elapsed > 0 && Number.isFinite(data.elapsed) ? data.elapsed : null);
      } catch (error) {
        if (error.fatal || run.cancelled || run.finished) throw error;
        samples.push(null);
      }
      const valid = samples.filter(value => value !== null);
      run.result.successful = valid.length;
      run.result.latencyMs = valid.length ? valid.reduce((a, b) => a + b, 0) / valid.length : null;
      const differences = samples.slice(1).flatMap((value, index) =>
        value !== null && samples[index] !== null ? [Math.abs(value - samples[index])] : []);
      run.result.jitterMs = differences.length ? differences.reduce((a, b) => a + b, 0) / differences.length : null;
      run.progress = run.kind === 'speed' ? (i + 1) / count * .25 : (i + 1) / count;
      emit(run);
    }
    if (!run.result.successful) throw new TestError('没有有效的 HTTPS 样本，请检查网络或稍后手动重试。');
  }
  async function speed(run) {
    await latency(run, 5);
    const download = [262144, 1048576, 4194304];
    const upload = [262144, 1048576];
    let downloadTime = 0, uploadTime = 0;
    let measuredDownload = 0, measuredUpload = 0;
    run.stage = 'download';
    for (let i = 0; i < download.length; i++) {
      emit(run);
      const size = download[i];
      const data = await request(run, `${DOWN}?bytes=${size}&tn=${encodeURIComponent(run.id)}-${i}`, { expectedBytes: size, maxBytes: size });
      run.result.downloadBytes += data.bytes.byteLength;
      if (data.elapsed >= 20) { downloadTime += data.elapsed; measuredDownload += data.bytes.byteLength; }
      run.result.downloadMbps = downloadTime ? measuredDownload * 8 / downloadTime / 1000 : null;
      run.progress = .25 + (i + 1) / download.length * .45;
      emit(run);
    }
    run.stage = 'upload';
    for (let i = 0; i < upload.length; i++) {
      check(run);
      emit(run);
      const payload = new Uint8Array(upload[i]);
      // Only random synthetic bytes, never files, logs or any personal content.
      if (!globalThis.crypto?.getRandomValues) throw new TestError('此浏览器无法生成测试数据，已停止上传。', true);
      for (let offset = 0; offset < payload.length; offset += 65536) {
        crypto.getRandomValues(payload.subarray(offset, Math.min(offset + 65536, payload.length)));
      }
      const data = await request(run, UP, { method: 'POST', body: payload, maxBytes: 8192 });
      run.result.uploadBytes += payload.length;
      if (data.elapsed >= 20) { uploadTime += data.elapsed; measuredUpload += payload.length; }
      run.result.uploadMbps = uploadTime ? measuredUpload * 8 / uploadTime / 1000 : null;
      run.progress = .7 + (i + 1) / upload.length * .3;
      emit(run);
    }
    if (run.result.downloadMbps === null || run.result.uploadMbps === null) {
      run.result.warnings.push('部分传输耗时不足 20 毫秒，样本过短，无法可靠估算对应速度。');
    }
  }
  function domainName(raw) {
    if (typeof raw !== 'string' || raw.length > 253) throw new TestError('请输入有效的公开域名。', true);
    const name = raw.trim().replace(/\.$/, '');
    if (!name || /[\s/:@?#\\%\[\]]/.test(name)) throw new TestError('只填写域名，不含协议、路径、端口或账号信息。', true);
    let ascii;
    try { ascii = new URL(`https://${name}/`).hostname.toLowerCase(); } catch (_) { throw new TestError('域名格式无效。', true); }
    const labels = ascii.split('.');
    if (ascii.length > 253 || labels.length < 2 || labels.some(label => !/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))
        || /^\d+(?:\.\d+){3}$/.test(ascii) || /^\d+$/.test(labels.at(-1))
        || /(?:^|\.)(?:localhost|local|localdomain|internal|intranet|lan|home|corp|private|onion|test|invalid)$/.test(ascii)
        || /(?:^|\.)home\.arpa$/.test(ascii)) {
      throw new TestError('请填写公开域名，不支持 IP、内网或本地域名。', true);
    }
    return ascii;
  }
  async function dns(run, args) {
    const name = domainName(args.name);
    const type = args.type;
    if (!Object.hasOwn(TYPES, type)) throw new TestError('不支持此 DNS 记录类型。', true);
    run.result.name = name;
    run.result.type = type;
    run.stage = 'dns';
    emit(run);
    const url = new URL(DNS);
    url.searchParams.set('name', name);
    url.searchParams.set('type', type);
    const data = await request(run, url.href, { headers: { Accept: 'application/dns-json' }, maxBytes: 65536 });
    let value;
    try { value = JSON.parse(new TextDecoder().decode(data.bytes)); } catch (_) { throw new TestError('DNS 服务返回格式异常。', true); }
    if (!value || !Number.isInteger(value.Status) || value.Status < 0 || value.Status > 15 || value.TC === true
        || !Array.isArray(value.Question) || value.Question.length !== 1
        || typeof value.Question[0]?.name !== 'string'
        || value.Question[0].name.toLowerCase().replace(/\.$/, '') !== name
        || value.Question[0].type !== TYPES[type]
        || (value.Answer !== undefined && !Array.isArray(value.Answer))) {
      throw new TestError('DNS 服务返回不完整或无效的数据。', true);
    }
    const answers = value.Answer || [];
    if (answers.length > 100 || answers.some(answer => typeof answer.name !== 'string' || answer.name.length > 255
        || !Number.isInteger(answer.type) || !Number.isInteger(answer.TTL) || answer.TTL < 0
        || typeof answer.data !== 'string' || answer.data.length > 4096)) {
      throw new TestError('DNS 记录格式异常。', true);
    }
    run.result.rcode = value.Status;
    run.result.dnssec = value.AD === true;
    run.result.answers = answers.map(answer => ({
      name: answer.name, type: TYPE_NAMES[answer.type] || `TYPE${answer.type}`, ttl: answer.TTL, data: answer.data,
    }));
    if (value.Status !== 0 && value.Status !== 3) {
      const reason = value.Status === 2 ? '解析器处理失败（SERVFAIL）'
        : value.Status === 5 ? '解析器拒绝查询（REFUSED）' : `解析器返回错误 RCODE ${value.Status}`;
      throw new TestError(`${reason}，无法判断记录是否存在。`, true);
    }
    run.progress = 1;
  }
  function start(kind, rawArgs, callback) {
    // Only one operation globally. Repeated user starts cancel the old operation.
    for (const id of runs.keys()) cancel(id, '已开始新测试，上一次测试已停止。');
    const id = `network-${Date.now()}-${++serial}`;
    const run = {
      id, kind, callback, controllers: new Set(), cancelled: false, finished: false,
      stage: 'warmup', progress: 0,
      result: { provider: kind === 'latency' ? '本站 HTTPS' : 'Cloudflare', startedAt: stamp(),
        samples: [], successful: 0, attempted: 0, latencyMs: null, jitterMs: null,
        downloadMbps: null, uploadMbps: null, downloadBytes: 0, uploadBytes: 0, warnings: [] },
    };
    runs.set(id, run);
    run.deadline = setTimeout(() => cancel(id, '已达到 45 秒时限，测试停止；未完成的数据不作为完整结果。'), 45000);
    // Queue execution so callers have their cancellation token before callbacks.
    Promise.resolve().then(async () => {
      try {
        check(run);
        if (globalThis.document?.hidden) throw new TestError('页面在后台，请回到前台后手动开始。', true);
        const args = JSON.parse(rawArgs || '{}');
        if (!args || typeof args !== 'object' || Array.isArray(args)) throw new TestError('请求参数无效。', true);
        if (kind === 'speed') await speed(run);
        else if (kind === 'latency') await latency(run, 10);
        else if (kind === 'dns') await dns(run, args);
        else throw new TestError('未知网络工具。', true);
        check(run);
        run.stage = 'done'; run.progress = 1;
        emit(run, 'complete');
      } catch (error) {
        if (!run.finished) emit(run, 'error', error instanceof TestError ? error.message : '网络工具遇到异常，请稍后手动重试。');
      }
    });
    return id;
  }
  globalThis.document?.addEventListener('visibilitychange', () => {
    if (document.hidden) for (const id of runs.keys()) cancel(id, '页面已转入后台，测试自动停止；返回后需手动开始。');
  });
  globalThis.addEventListener?.('pagehide', () => { for (const id of runs.keys()) cancel(id); });
  globalThis.timeNestNetwork = Object.freeze({
    environment, history, clearHistory, start, cancel,
    openUrl(url) { if (LINKS.has(url)) globalThis.open(url, '_blank', 'noopener,noreferrer'); },
  });
})();
