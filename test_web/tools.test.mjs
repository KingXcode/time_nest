import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../web/tools.js', import.meta.url), 'utf8');
const context = {};
vm.runInNewContext(source, context);
const geometry = context.shikeTools.geometry;
test('image cropping stays centered and inside the source rectangle', () => {
  const g = geometry(1600,900,{width:600,height:600,ratio:1});
  assert.equal(g.sx,350); assert.equal(g.sy,0); assert.equal(g.sw,900); assert.equal(g.sh,900);
  const p = geometry(900,1600,{width:600,height:338,ratio:16/9});
  assert.equal(p.sx,0); assert.equal(p.sw,900); assert.equal(p.sh,506.25);
  assert.equal(p.sy,(1600-506.25)/2);
});
test('image dimensions are bounded and uncropped images keep their full source', () => {
  const g=geometry(400,200,{width:200,height:100,ratio:0});
  assert.equal(g.sw,400);assert.equal(g.sh,200);assert.equal(g.sx,0);
  for(const width of [0,2049,NaN,1.5]) assert.throws(()=>geometry(100,100,{width,height:10}),/2048/);
});
test('blocked local storage does not prevent tool initialization',()=>{
  assert.equal(context.shikeTools.readPalette(),'[]');
  assert.equal(context.shikeTools.savePalette('[]'),false);
});
