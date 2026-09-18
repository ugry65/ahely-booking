import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { check } from './check-release-evidence.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'release-evidence-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const data = Buffer.from('Elfogadott UAT – történeti bizonyíték\n');
  writeFileSync(join(root, 'proof.md'), data);
  const sha = createHash('sha1').update(Buffer.from('blob ' + data.length + '\0')).update(data).digest('hex');
  const manifest = {version:1, evidence:[{path:'proof.md',sha}], features:[
    {id:'email',required:true,state:'absent',artifacts:[{path:'worker.ts',sha:null},{path:'schema.sql',sha:null}]}
  ], releaseBlockers:['Live deployment unverified']};
  return {root,manifest,sha,data};
}
test('truthful absent state passes consistency but blocks release', t => {
  const {root,manifest}=fixture(t);
  assert.deepEqual(check(root,manifest),[]);
  assert.equal(check(root,manifest,true).length,2);
});
test('partial integration cannot silently pass', t => {
  const {root,manifest}=fixture(t);
  writeFileSync(join(root,'worker.ts'),'worker');
  assert.match(check(root,manifest)[0],/Code\/evidence drift/);
});
test('historical evidence changes detected', t => {
  const {root,manifest}=fixture(t);
  writeFileSync(join(root,'proof.md'),'All PASS');
  assert.match(check(root,manifest)[0],/Historical evidence mismatch/);
});
test('present implementation deletion and modification detected', t => {
  const {root,manifest,sha,data}=fixture(t);
  manifest.features[0]={id:'email',required:true,state:'present',artifacts:[{path:'worker.ts',sha}]};
  assert.equal(check(root,manifest).length,1);
  writeFileSync(join(root,'worker.ts'),data);
  assert.deepEqual(check(root,manifest),[]);
  writeFileSync(join(root,'worker.ts'),'changed');
  assert.equal(check(root,manifest).length,1);
});
test('present code alone does not clear release blockers', t => {
  const {root,manifest,sha}=fixture(t);
  manifest.features[0]={id:'email',required:true,state:'present',artifacts:[{path:'proof.md',sha}]};
  assert.equal(check(root,manifest,true).length,1);
  manifest.releaseBlockers=[];
  assert.deepEqual(check(root,manifest,true),[]);
});
test('empty or malformed manifests fail closed', t => {
  const {root,manifest}=fixture(t);
  assert.throws(()=>check(root,{...manifest,features:[]}),/Invalid/);
  manifest.features[0].state='ready';
  assert.throws(()=>check(root,manifest),/Invalid/);
});
test('path traversal rejected', t => {
  const {root,manifest}=fixture(t);
  manifest.evidence[0].path='../proof.md';
  assert.throws(()=>check(root,manifest),/Unsafe/);
});
