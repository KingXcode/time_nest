// Browser-only file operations. User content never leaves this page.
(() => {
  'use strict';
  const maxSide = 2048;
  const paletteKey = 'shike.tools.palette.v1';
  function loadImage(data) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('无法读取图片，请选择 PNG、JPEG 或 WebP'));
      img.src = data;
    });
  }
  function canvas(width, height) {
    const node = document.createElement('canvas');
    node.width = width; node.height = height;
    return node;
  }
  function geometry(width, height, options) {
    const w = Number(options.width), h = Number(options.height);
    if (![w, h].every(n => Number.isInteger(n) && n >= 1 && n <= maxSide)) throw new Error('输出尺寸须在 1～2048 像素之间');
    let sw = width, sh = height;
    const ratio = Number(options.ratio);
    if (ratio > 0) { if (sw / sh > ratio) sw = sh * ratio; else sh = sw / ratio; }
    return { sx: (width - sw) / 2, sy: (height - sh) / 2, sw, sh, w, h };
  }
  let choosing = false;
  function pickImage() {
    if (choosing) return Promise.resolve(null);
    choosing = true;
    return new Promise((resolve, reject) => {
      const input = document.createElement('input');
      input.type = 'file'; input.accept = 'image/png,image/jpeg,image/webp'; input.hidden = true;
      let finished = false;
      const finish = (result, error) => {
        if (finished) return;
        finished = true; choosing = false;
        input.remove(); window.removeEventListener('focus', onFocus);
        if (error) reject(error); else resolve(result);
      };
      // Older Safari does not fire `cancel`. Give its change event time to run.
      const onFocus = () => window.setTimeout(() => { if (!input.files?.length) finish(null); }, 500);
      window.addEventListener('focus', onFocus);
      input.addEventListener('cancel', () => finish(null));
      input.addEventListener('change', async () => {
        const file = input.files?.[0];
        if (!file) { finish(null); return; }
        let url;
        try {
          if (file.size > 32 * 1024 * 1024) throw new Error('图片请小于 32 MB');
          if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) throw new Error('请选择 PNG、JPEG 或 WebP 图片');
          url = URL.createObjectURL(file);
          const img = await loadImage(url);
          const scale = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight));
          const width = Math.max(1, Math.round(img.naturalWidth * scale)), height = Math.max(1, Math.round(img.naturalHeight * scale));
          const out = canvas(width, height);
          out.getContext('2d').drawImage(img, 0, 0, width, height);
          finish(JSON.stringify({ name: file.name, sourceSize: file.size, width, height, dataUrl: out.toDataURL('image/png') }));
          out.width = out.height = 0;
        } catch (error) { finish(null, error); }
        finally { if (url) URL.revokeObjectURL(url); }
      });
      document.body.append(input); input.click();
    });
  }
  async function processImage(data, rawOptions) {
    const options = JSON.parse(rawOptions);
    const img = await loadImage(data);
    const { sx, sy, sw, sh, w, h } = geometry(img.naturalWidth, img.naturalHeight, options);
    const out = canvas(w, h), ctx = out.getContext('2d');
    const format = options.format === 'JPEG' ? 'image/jpeg' : 'image/png';
    if (format === 'image/jpeg') { ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, w, h); }
    ctx.drawImage(img, sx, sy, sw, sh, 0, 0, w, h);
    const result = out.toDataURL(format, Math.max(.1, Math.min(1, Number(options.quality) || .85)));
    out.width = out.height = 0;
    return result;
  }
  async function sampleColor(data, x, y) {
    const img = await loadImage(data);
    const out = canvas(1, 1), ctx = out.getContext('2d');
    ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, 1, 1);
    const px = Math.min(img.naturalWidth - 1, Math.max(0, Math.floor(x * img.naturalWidth)));
    const py = Math.min(img.naturalHeight - 1, Math.max(0, Math.floor(y * img.naturalHeight)));
    ctx.drawImage(img, px, py, 1, 1, 0, 0, 1, 1);
    return '#' + [...ctx.getImageData(0, 0, 1, 1).data].slice(0, 3).map(n => n.toString(16).padStart(2, '0')).join('').toUpperCase();
  }
  function download(data, name) {
    if (!/^data:image\/(png|jpeg);base64,/.test(data)) throw new Error('不支持的文件格式');
    const [prefix, encoded] = data.split(',');
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], { type: prefix.slice(5, prefix.indexOf(';')) }));
    const a = document.createElement('a');
    a.href = url; a.download = name; document.body.append(a); a.click(); a.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 60000);
  }
  globalThis.shikeTools = {
    pickImage, processImage, sampleColor, download, geometry,
    readPalette() { try { return localStorage.getItem(paletteKey) || '[]'; } catch (_) { return '[]'; } },
    savePalette(value) { try { localStorage.setItem(paletteKey, value); return true; } catch (_) { return false; } },
  };
})();
