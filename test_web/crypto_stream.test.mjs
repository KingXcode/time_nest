import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/dashboard.js', import.meta.url), 'utf8');
const START = Date.parse('2026-10-19T00:00:00Z');
function harness() {
  let now=START, next=0;
  const sockets=[],timers=new Map(),events=[],listeners=new Map();
  class Clock extends Date { constructor(...args){super(...(args.length?args:[now]));} static now(){return now;} }
  class Socket {
    constructor(url){this.url=url;sockets.push(this);}
    close(){this.closed=true;}
    open(){this.onopen?.();}
    frame(data){this.onmessage?.({data:JSON.stringify(data)});}
  }
  const document={hidden:false,addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:(name)=>listeners.delete(name)};
  const context={URL,URLSearchParams,AbortController,Date:Clock,WebSocket:Socket,document,
    localStorage:{getItem:()=>null,setItem:()=>{}},
    setTimeout:(fn,delay)=>{const id=++next;timers.set(id,{fn,at:now+delay});return id;},clearTimeout:id=>timers.delete(id)};
  vm.runInNewContext(source,context);
  function advance(ms){const target=now+ms;for(;;){const ready=[...timers].filter(([,t])=>t.at<=target).sort((a,b)=>a[1].at-b[1].at)[0];if(!ready)break;now=ready[1].at;timers.delete(ready[0]);ready[1].fn();}now=target;}
  return {api:context.timeNestDashboard,events,sockets,timers,document,advance,now:()=>now,
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

function depth(id=10, symbol='BTCUSDT') {
  return {stream:`${symbol.toLowerCase()}@depth20`,data:{lastUpdateId:id,
    bids:[['100.00','2.00000000'],['99.99','1.2']],asks:[['100.01','3.5'],['100.02','0.01']]}};
}
test('depth snapshots without event timestamps are atomic, validated and isolated by stream and update id',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  assert.ok(new URL(ws.url).searchParams.get('streams').includes('btcusdt@depth20'));
  ws.frame(depth());const event=h.events.at(-1);
  assert.equal(event.type,'depth');assert.equal(event.symbol,'BTCUSDT');assert.equal(event.book.priceDecimals,2);
  assert.equal(event.book.bids[0].quantity,2);assert.equal(event.book.asks[0].price,100.01);
  const before=h.events.length;
  ws.frame(depth(9));ws.frame(depth(12,'ETHUSDT'));
  const crossed=depth(11);crossed.data.bids[0][0]='101';ws.frame(crossed);
  const unsorted=depth(11);unsorted.data.asks.reverse();ws.frame(unsorted);
  const invalid=depth(11);invalid.data.bids[0][1]='NaN';ws.frame(invalid);
  const zero=depth(11);zero.data.asks[0][1]='0';ws.frame(zero);
  const duplicate=depth(11);duplicate.data.bids[1][0]='100.00';ws.frame(duplicate);
  assert.equal(h.events.length,before);
  h.advance(1000);ws.frame(depth(10));assert.equal(h.events.at(-1).eventTime,h.now(),'equal update IDs are valid fresh complete snapshots');
  const obsolete=ws.onmessage;ws.onerror();h.advance(1000);h.sockets[1].open();h.sockets[1].frame(depth(1));
  assert.equal(h.events.at(-1).book.lastUpdateId,1,'a new connection starts a fresh depth sequence');
  const count=h.events.length;obsolete({data:JSON.stringify(depth(100))});assert.equal(h.events.length,count);
  h.api.unsubscribeCrypto(id);
});
test('silent depth is detected while ticker and candles keep flowing; pause stops all streams',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  for(let i=0;i<4;i++){h.advance(5000);if(!ws.closed){ws.frame(ticker(h.now()));ws.frame(candle(h.now()));}}
  assert.equal(ws.closed,true);assert.equal(h.events.at(-1).status,'reconnecting');
  h.api.unsubscribeCrypto(id);assert.equal(h.timers.size,0);
});

test('fresh complete depth snapshots keep the shared connection healthy without timestamp fields',()=>{
  const h=harness(),id=h.start(),ws=h.sockets[0];ws.open();
  for(let i=0;i<7;i++) {h.advance(3000);ws.frame(ticker(h.now()));ws.frame(candle(h.now()));ws.frame(depth(i+10));}
  assert.notEqual(ws.closed,true);assert.equal(h.sockets.length,1);assert.equal(h.events.at(-1).type,'depth');
  h.visibility(true);assert.equal(ws.closed,true);assert.equal(h.timers.size,0);h.api.unsubscribeCrypto(id);
});
