import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/dashboard.js', import.meta.url), 'utf8');
const START = Date.parse('2026-10-19T00:00:00Z');
function harness(options = {}) {
  let now=START, next=0;
  const sockets=[],timers=new Map(),events=[],listeners=new Map(),requests=[],storage=new Map();
  class Clock extends Date { constructor(...args){super(...(args.length?args:[now]));} static now(){return now;} }
  class Socket {
    constructor(url){this.url=url;sockets.push(this);}
    close(){this.closed=true;}
    open(){this.onopen?.();}
    frame(data){this.onmessage?.({data:JSON.stringify(data)});}
  }
  const document={hidden:false,addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:(name)=>listeners.delete(name)};
  const context={URL,URLSearchParams,AbortController,Date:Clock,WebSocket:Socket,document,
    localStorage:{getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,value)},
    fetch:async(url,init)=>{requests.push({url,init});return options.fetch ? options.fetch(requests.length,url,init) : response(snapshot());},
    setTimeout:(fn,delay)=>{const id=++next;timers.set(id,{fn,at:now+delay});return id;},clearTimeout:id=>timers.delete(id)};
  vm.runInNewContext(source,context);
  function advance(ms){const target=now+ms;for(;;){const ready=[...timers].filter(([,t])=>t.at<=target).sort((a,b)=>a[1].at-b[1].at)[0];if(!ready)break;now=ready[1].at;timers.delete(ready[0]);ready[1].fn();}now=target;}
  return {api:context.timeNestDashboard,events,sockets,timers,document,advance,requests,storage,now:()=>now,
    start:(symbol='BTCUSDT',interval='1h')=>context.timeNestDashboard.subscribeCrypto(JSON.stringify({symbol,interval}),raw=>events.push(JSON.parse(raw))),
    visibility:hidden=>{document.hidden=hidden;listeners.get('visibilitychange')?.();},listeners};
}
function ticker(time=START,symbol='BTCUSDT',price='100') {return {stream:`${symbol.toLowerCase()}@ticker`,data:{e:'24hrTicker',E:time,s:symbol,c:price,P:'1.2',h:'110',l:'90',v:'20',q:'2000',O:time-86400000,C:time}};}
function candle(time=START,symbol='BTCUSDT',interval='1h') {return {stream:`${symbol.toLowerCase()}@kline_${interval}`,data:{e:'kline',E:time,s:symbol,k:{s:symbol,i:interval,t:START,T:START+3599999,o:'100',h:'110',l:'90',c:'101',v:'10',q:'1010',x:false}}};}

test('market-only combined socket carries six tickers and selected UTC kline and depth; price live requires ticker and kline',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];
  assert.equal(new URL(ws.url).hostname,'data-stream.binance.vision');
  assert.equal(new URL(ws.url).searchParams.get('streams').split('/').length,8);
  ws.open();ws.frame(ticker());
  assert.equal(h.events.some(e=>e.status==='live'),false);
  ws.frame(candle());
  assert.equal(h.events.at(-1).status,'live');
  assert.equal(h.events.find(e=>e.type==='quote').quote.price,100);
  assert.equal(h.events.find(e=>e.type==='candle').candle.quoteVolume,1010);
  h.api.unsubscribeCrypto(id);assert.equal(ws.closed,true);assert.equal(h.timers.size,0);assert.equal(h.listeners.size,0);
});

test('duplicate, out-of-order, wrong symbol/period and malformed payloads never reach Dart',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(ticker());ws.frame(candle());
  const before=h.events.length;
  ws.frame(ticker());ws.frame(ticker(START-1));ws.frame(candle(START,'ETHUSDT'));ws.frame(candle(START,'BTCUSDT','1d'));
  ws.frame(ticker(START+1,'BTCUSDT','NaN'));
  const malformed=candle(START+1);malformed.data.k.h='1';ws.frame(malformed);
  assert.equal(h.events.length,before);
  h.advance(1000);ws.frame(ticker(START+1000,'BTCUSDT','102'));assert.equal(h.events.at(-1).quote.price,102);
  h.api.unsubscribeCrypto(id);
});

test('disconnect retries once with bounded backoff and reconnect requests history resync',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();const obsolete=ws.onmessage;
  ws.onerror();assert.equal(h.events.at(-1).status,'reconnecting');assert.equal(ws.closed,true);
  h.advance(999);assert.equal(h.sockets.length,1);h.advance(1);assert.equal(h.sockets.length,2);
  h.sockets[1].open();assert.equal(h.events.at(-1).resync,true);
  const n=h.events.length;obsolete({data:JSON.stringify(ticker())});assert.equal(h.events.length,n);
  h.api.unsubscribeCrypto(id);h.advance(60000);assert.equal(h.sockets.length,2);
});

test('silent selected kline is detected even when other ticker frames keep arriving',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  for(let i=0;i<4;i++){h.advance(5000);ws.frame(ticker(h.now(),'ETHUSDT'));}
  assert.equal(ws.closed,true);assert.equal(h.events.at(-1).status,'reconnecting');
  h.api.unsubscribeCrypto(id);
});

test('hidden pages close socket and cancel timers; resume and symbol switch isolate connections',()=>{
  const h=harness(),id=h.start();h.sockets[0].open();h.visibility(true);
  assert.equal(h.sockets[0].closed,true);assert.equal(h.timers.size,0);
  h.advance(300000);assert.equal(h.sockets.length,1);h.visibility(false);assert.equal(h.sockets.length,2);
  h.api.unsubscribeCrypto(id);const next=h.start('ETHUSDT','1d');
  assert.ok(h.sockets.at(-1).url.endsWith('ethusdt@kline_1d'));
  h.api.unsubscribeCrypto(next);assert.equal(h.timers.size,0);
});

test('invalid choices fail before dialing; server shutdown triggers resubscribe',()=>{
  const h=harness();assert.throws(()=>h.start('BTCUSDT','__proto__'));assert.equal(h.sockets.length,0);
  const id=h.start();h.sockets[0].open();h.sockets[0].frame({e:'serverShutdown'});
  assert.equal(h.events.at(-1).status,'reconnecting');h.advance(1000);assert.equal(h.sockets.length,2);h.api.unsubscribeCrypto(id);
});

const settle = async () => { for(let i=0;i<8;i++) await new Promise(setImmediate); };
function deferred() { let resolve; const promise=new Promise(done=>resolve=done);return {promise,resolve}; }
function snapshot(lastUpdateId=10) {
  return {lastUpdateId,bids:[['100.00','2.00000000'],['99.99','1.2']],asks:[['100.01','3.5'],['100.02','0.01']]};
}
function response(data, status=200, headers={}) {
  return new Response(JSON.stringify(data),{status,headers:{'content-type':'application/json',...headers}});
}
function depth(u=11, {U=u-1,symbol='BTCUSDT',b=[['100.00','2.0']],a=[]}={}) {
  return {stream:`${symbol.toLowerCase()}@depth`,data:{e:'depthUpdate',E:START,s:symbol,U,u,b,a}};
}
const copies = h => h.events.filter(e=>e.type==='depth');
const copy = h => copies(h).at(-1)?.book;
const bookStatus = h => h.events.filter(e=>e.type==='depthStatus').at(-1)?.status;

test('diff stream buffers before REST, discards snapshot-covered events and replays newer events atomically',async()=>{
  const pending=deferred(),h=harness({fetch:()=>pending.promise}),id=h.start(),ws=h.sockets[0];ws.open();
  assert.ok(new URL(ws.url).searchParams.get('streams').split('/').includes('btcusdt@depth'));
  ws.frame(depth(100,{U:99,b:[['100.00','999']]}));
  assert.equal(h.requests.length,1);
  const url=new URL(h.requests[0].url);
  assert.equal(url.hostname,'data-api.binance.vision');assert.equal(url.pathname,'/api/v3/depth');
  assert.equal(url.searchParams.get('symbol'),'BTCUSDT');assert.equal(url.searchParams.get('limit'),'5000');
  assert.equal(h.requests[0].init.cache,'no-store');assert.equal(h.requests[0].init.credentials,'omit');
  ws.frame(depth(102,{U:101,b:[['100.00','7']]}));
  ws.frame(depth(103,{U:102,b:[['100.00','4']],a:[['100.01','0'],['101.00','1.5']]}));
  assert.equal(copies(h).length,0);assert.equal(bookStatus(h),'syncing');
  pending.resolve(response(snapshot(100)));await settle();
  assert.equal(copies(h).length,1);assert.equal(copy(h).lastUpdateId,103);
  assert.equal(copy(h).bids[0].quantity,4);assert.equal(copy(h).asks[0].price,100.02);
  assert.equal(copy(h).priceDecimals,2);assert.equal(bookStatus(h),'live');
  assert.ok(!h.storage.get('shike.dashboard.cache.v1')?.includes('lastUpdateId'));
  h.api.unsubscribeCrypto(id);
});

test('a snapshot older than first buffered U retries with backoff and cannot be shown as live',async()=>{
  const h=harness({fetch:n=>response(snapshot(n===1?99:101))}),id=h.start(),ws=h.sockets[0];ws.open();
  ws.frame(depth(102,{U:100}));await settle();
  assert.equal(copies(h).length,0);assert.equal(bookStatus(h),'retrying');assert.equal(h.requests.length,1);
  h.advance(999);await settle();assert.equal(h.requests.length,1);
  h.advance(1);await settle();assert.equal(h.requests.length,2);assert.equal(copy(h).lastUpdateId,102);
  h.api.unsubscribeCrypto(id);
});

test('snapshot alone waits for its first bridge; U=id+1, overlapping ranges and duplicate u boundaries are handled',async()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  ws.frame(depth(10,{U:9}));await settle();assert.equal(copies(h).length,0);
  ws.frame(depth(11,{U:11,b:[['100.00','8']]}));assert.equal(copy(h).bids[0].quantity,8);
  const count=copies(h).length;
  ws.frame(depth(11,{U:10,b:[['100.00','999']]}));ws.frame(depth(9,{U:8}));
  assert.equal(copies(h).length,count);
  ws.frame(depth(13,{U:11,b:[['100.00','3'],['100.00','5']]}));
  assert.equal(copy(h).lastUpdateId,13);assert.equal(copy(h).bids[0].quantity,5);
  h.api.unsubscribeCrypto(id);
});

test('zero deletes existing or absent prices while the entire trusted range stays available for grouping',async()=>{
  const initial={lastUpdateId:10,bids:Array.from({length:30},(_,i)=>[(100-i*.01).toFixed(2),'1']),asks:Array.from({length:30},(_,i)=>[(101+i*.01).toFixed(2),'2'])};
  const h=harness({fetch:()=>response(initial)}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());await settle();
  assert.equal(copy(h).bids.length,30);assert.equal(copy(h).asks.length,30);
  ws.frame(depth(12,{U:12,b:[['100.000','0'],['90','0'],['100.5','3']],a:[['101.00','0']]}));
  assert.equal(copy(h).bids[0].price,100.5);assert.equal(copy(h).bids[0].quantity,3);
  assert.equal(copy(h).bids[1].price,99.99);assert.equal(copy(h).asks[0].price,101.01);
  assert.equal(copy(h).asks.at(-1).price,101.29);assert.equal(h.requests.length,1);
  h.api.unsubscribeCrypto(id);
});

test('a sequence gap freezes the copy, refetches and replays without disrupting ticker/kline',async()=>{
  const pending=deferred(),h=harness({fetch:n=>n===1?response(snapshot()):pending.promise}),id=h.start(),ws=h.sockets[0];ws.open();
  ws.frame(depth());await settle();ws.frame(ticker());ws.frame(candle());
  assert.equal(h.events.at(-1).status,'live');
  ws.frame(depth(15,{U:14,b:[['100','7']]}));
  assert.equal(bookStatus(h),'syncing');assert.equal(copy(h).lastUpdateId,11);
  h.advance(1000);await settle();assert.equal(h.requests.length,2);
  ws.frame(depth(16,{U:16,b:[['100','9']]}));assert.equal(copy(h).lastUpdateId,11);
  pending.resolve(response(snapshot(14)));await settle();
  assert.equal(copy(h).lastUpdateId,16);assert.equal(copy(h).bids[0].quantity,9);
  assert.equal(bookStatus(h),'live');assert.equal(h.sockets.length,1);assert.notEqual(ws.closed,true);
  h.api.unsubscribeCrypto(id);
});

test('foreign streams do not mutate the copy; malformed selected diffs invalidate it before any partial update',async()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());await settle();
  const before=copies(h).length;ws.frame(depth(20,{symbol:'ETHUSDT'}));assert.equal(copies(h).length,before);
  ws.frame(depth(12,{U:12,b:[['100','8'],['99','-1']]}));
  assert.equal(copies(h).length,before);assert.equal(copy(h).bids[0].quantity,2);assert.equal(bookStatus(h),'retrying');
  assert.notEqual(ws.closed,true);h.api.unsubscribeCrypto(id);
});

test('crossed snapshots and crossed results never publish; later complete snapshots recover',async()=>{
  const wrong=snapshot();wrong.bids[0][0]='102';
  const h=harness({fetch:n=>response(n===1?wrong:snapshot(12))}),id=h.start(),ws=h.sockets[0];ws.open();
  ws.frame(depth(11));await settle();assert.equal(copies(h).length,0);
  h.advance(1000);await settle();assert.equal(copies(h).length,0,'snapshot-only still waits for a diff');
  ws.frame(depth(13,{U:13}));assert.equal(copy(h).lastUpdateId,13);
  const before=copies(h).length;ws.frame(depth(14,{U:14,b:[['102','3']]}));
  assert.equal(copies(h).length,before);assert.equal(bookStatus(h),'syncing');
  h.api.unsubscribeCrypto(id);
});

test('disconnect cancels REST and late old responses cannot overwrite a new connection with a fresh sequence',async()=>{
  const pending=deferred(),h=harness({fetch:n=>n===1?pending.promise:response(snapshot())}),id=h.start(),ws=h.sockets[0];ws.open();
  ws.frame(depth(1001,{U:1000}));const obsolete=ws.onmessage;
  ws.onerror();assert.equal(h.requests[0].init.signal.aborted,true);
  h.advance(1000);const next=h.sockets.at(-1);next.open();next.frame(depth());await settle();
  assert.equal(copy(h).lastUpdateId,11);
  pending.resolve(response(snapshot(1000)));await settle();obsolete({data:JSON.stringify(depth(2000,{U:1999}))});
  assert.equal(copy(h).lastUpdateId,11);assert.equal(h.requests.length,2);
  h.api.unsubscribeCrypto(id);assert.equal(h.timers.size,0);
});

test('hide/unsubscribe cancels snapshot, backoff and socket; symbol switches fence late responses',async()=>{
  const pending=deferred(),h=harness({fetch:()=>pending.promise}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());
  h.visibility(true);assert.equal(ws.closed,true);assert.equal(h.requests[0].init.signal.aborted,true);assert.equal(h.timers.size,0);
  h.api.unsubscribeCrypto(id);
  h.document.hidden=false;const eth=h.start('ETHUSDT');h.sockets.at(-1).open();
  pending.resolve(response(snapshot()));await settle();assert.equal(copies(h).length,0);
  h.api.unsubscribeCrypto(eth);assert.equal(h.timers.size,0);
});

test('REST 429 Retry-After prevents a fetch loop while valid depth keeps the socket alive',async()=>{
  const h=harness({fetch:n=>n===1?response({},429,{'retry-after':'120'}):response(snapshot())}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());await settle();
  assert.equal(bookStatus(h),'retrying');
  for(let i=0;i<12;i++) {
    h.advance(10000);ws.frame(ticker(h.now()));ws.frame(candle(h.now()));
    const frame=depth(i+12,{U:i+12});frame.data.E=h.now();ws.frame(frame);await settle();
    assert.equal(h.requests.length,i===11?2:1);
  }
  assert.equal(copy(h).lastUpdateId,23);assert.notEqual(ws.closed,true);
  h.api.unsubscribeCrypto(id);
});

test('snapshot timeout marks retrying, backs off and cleanup aborts every pending fetch',async()=>{
  const h=harness({fetch:(_n,_url,init)=>new Promise((_resolve,reject)=>init.signal.addEventListener('abort',()=>{
    const error=new Error('aborted');error.name='AbortError';reject(error);
  }))}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());
  h.advance(10000);await settle();
  assert.equal(h.requests[0].init.signal.aborted,true);assert.equal(bookStatus(h),'retrying');assert.equal(copies(h).length,0);
  h.advance(999);await settle();assert.equal(h.requests.length,1);
  h.advance(1);await settle();assert.equal(h.requests.length,2);
  h.api.unsubscribeCrypto(id);await settle();assert.equal(h.requests[1].init.signal.aborted,true);assert.equal(h.timers.size,0);
});

test('buffer overflow replaces an unfinished bootstrap and ignores its cancelled response',async()=>{
  const pending=deferred(),h=harness({fetch:n=>n===1?pending.promise:response(snapshot())}),id=h.start(),ws=h.sockets[0];ws.open();
  for(let i=0;i<1001;i++) ws.frame(depth());
  assert.equal(h.requests[0].init.signal.aborted,true);assert.equal(copies(h).length,0);
  pending.resolve(response(snapshot()));await settle();assert.equal(copies(h).length,0);
  h.advance(1000);await settle();assert.equal(h.requests.length,2);assert.equal(copy(h).lastUpdateId,11);
  h.api.unsubscribeCrypto(id);
});

test('unknown prices beyond a full snapshot cannot be promoted as a complete top twenty',async()=>{
  const initial={lastUpdateId:10,bids:Array.from({length:5000},(_,i)=>[(100-i*.01).toFixed(2),'1']),asks:[['101','2']]};
  const h=harness({fetch:()=>response(initial)}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());await settle();
  const before=copies(h).length;
  ws.frame(depth(12,{U:12,b:[...initial.bids.slice(0,4981).map(([p])=>[p,'0']),['40','1']]}));
  assert.equal(copies(h).length,before);assert.equal(bookStatus(h),'syncing');
  h.api.unsubscribeCrypto(id);
});

test('silent depth is detected while ticker and candles keep flowing; pause stops all streams',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  for(let i=0;i<4;i++){h.advance(5000);if(!ws.closed){ws.frame(ticker(h.now()));ws.frame(candle(h.now()));}}
  assert.equal(ws.closed,true);assert.equal(h.events.at(-1).status,'reconnecting');
  h.api.unsubscribeCrypto(id);assert.equal(h.timers.size,0);
});

test('sequential diff frames keep the shared connection healthy and background clears every timer',async()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth());await settle();
  for(let i=0;i<7;i++) {h.advance(3000);ws.frame(ticker(h.now()));ws.frame(candle(h.now()));ws.frame(depth(i+12,{U:i+12}));await settle();}
  assert.notEqual(ws.closed,true);assert.equal(h.sockets.length,1);assert.equal(copy(h).lastUpdateId,18);
  h.visibility(true);assert.equal(ws.closed,true);assert.equal(h.timers.size,0);h.api.unsubscribeCrypto(id);
});


test('5000-level bootstrap publishes all trusted depth and ignores unknown outer updates',async()=>{
  const initial={lastUpdateId:10,bids:Array.from({length:5000},(_,i)=>[(100000-i*.5).toFixed(2),'1']),asks:Array.from({length:5000},(_,i)=>[(100000.01+i*.5).toFixed(2),'2'])};
  const h=harness({fetch:()=>response(initial)}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth(11,{U:10,b:[],a:[]}));await settle();
  let current=copy(h);
  assert.equal(current.bids.length,5000);assert.equal(current.asks.length,5000);
  assert.equal(current.bidFloor,97500.5);assert.equal(current.askCeiling,102499.51);
  ws.frame(depth(12,{U:12,b:[['98000','9'],['97000','123']],a:[['102000.01','7'],['103000','456']]}));
  current=copy(h);
  assert.equal(current.bids.find(r=>r.price===98000).quantity,9);
  assert.equal(current.asks.find(r=>r.price===102000.01).quantity,7);
  assert.equal(current.bids.some(r=>r.price===97000),false);
  assert.equal(current.asks.some(r=>r.price===103000),false);
  assert.equal(h.requests.length,1);
  assert.equal(current.lastUpdateId,12);assert.equal(bookStatus(h),'live');
  h.api.unsubscribeCrypto(id);
});

test('growth beyond 10000 known prices per side restarts instead of publishing an unbounded copy',async()=>{
  const initial={lastUpdateId:10,bids:Array.from({length:5000},(_,i)=>[(100000-i*.01).toFixed(2),'1']),asks:[['100001','2']]};
  const h=harness({fetch:()=>response(initial)}),id=h.start(),ws=h.sockets[0];ws.open();ws.frame(depth(11,{U:10,b:[]}));await settle();
  const before=copies(h).length;
  ws.frame(depth(12,{U:12,b:Array.from({length:6000},(_,i)=>[(99999.9999-i*.0001).toFixed(4),'1'])}));
  assert.equal(copies(h).length,before);assert.equal(bookStatus(h),'syncing');
  h.api.unsubscribeCrypto(id);
});
