/* Fixed configuration for TradingView's official iframe widget.
 * The provider URL is emitted by its official embed configurator.
 * No provider JavaScript executes in this document or application origin.
 * No API calls, quote extraction or application data access.
 */
(() => {
  'use strict';
  const indices = Object.freeze({
    shanghai: ['SSE:000001', '上证指数'],
    shenzhen: ['SZSE:399001', '深证成指'],
    csi300: ['SSE:000300', '沪深300'],
    chinext: ['SZSE:399006', '创业板指'],
    star50: ['SSE:000688', '科创50'],
    allshare: ['SSE:000985', '中证全指'],
  });
  const query = new URLSearchParams(location.search);
  const id = query.get('index');
  const [symbol, name] = Object.hasOwn(indices, id) ? indices[id] : indices.shanghai;
  const interval = ['D', 'W', 'M'].includes(query.get('interval')) ? query.get('interval') : 'D';
  const technical = query.get('kind') === 'technical';
  const source = document.getElementById('source');
  source.href = `https://www.tradingview.com/symbols/${symbol.replace(':', '-')}/`;
  source.firstElementChild.textContent = `${name}${technical ? '技术面' : '图表'}`;
  const status = document.getElementById('status');
  if (technical && symbol === 'SSE:000688') {
    status.textContent = '科创50 技术评级暂缺，提供方目前没有该指数的评级数据。';
    return;
  }
  const frame = document.createElement('iframe');
  frame.title = `${name} · TradingView ${technical ? '日线技术面' : '历史走势图'}`;
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox');
  frame.setAttribute('referrerpolicy', 'no-referrer');
  const config = technical ? {
    interval: '1D', width: '100%', height: '100%', symbol,
    isTransparent: false, showIntervalTabs: false,
    displayMode: 'single', colorTheme: 'dark', locale: 'zh_CN',
  } : {
    autosize: true,
    width: '100%',
    height: '100%',
    symbol,
    interval,
    timezone: 'Asia/Shanghai',
    theme: 'dark',
    style: '1',
    locale: 'zh_CN',
    allow_symbol_change: false,
    hide_top_toolbar: true,
    hide_side_toolbar: true,
    save_image: false,
    withdateranges: false,
    support_host: 'https://www.tradingview.com',
  };
  const endpoint = technical ? 'technical-analysis' : 'advanced-chart';
  frame.src = `https://www.tradingview-widget.com/embed-widget/${endpoint}/?locale=zh_CN#` + encodeURIComponent(JSON.stringify(config));
  // A frame load is not proof of valid market data. Do not inspect its content
  // or claim success. Provider errors and attribution remain visible.
  const timer = setTimeout(() => {
    status.textContent = '未显示图表？服务可能暂时不可用，请重试或打开上方 TradingView 来源。';
  }, 18000);
  frame.onerror = () => {
    clearTimeout(timer);
    status.textContent = '图表服务暂不可用，请检查网络，或打开上方 TradingView 来源。';
  };
  window.addEventListener('pagehide', () => clearTimeout(timer), { once: true });
  document.getElementById('widget').appendChild(frame);
})();
