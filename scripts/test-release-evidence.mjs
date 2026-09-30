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
  writeFileSync(join(root, 'decision.md'), data);
  writeFileSync(join(root, 'observed.md'), data);
  const sha = createHash('sha1').update(Buffer.from('blob ' + data.length + '\0')).update(data).digest('hex');
  const manifest = {version:2, evidence:[{path:'proof.md',sha}], features:[
    {id:'email',required:true,state:'absent',artifacts:[{path:'worker.ts',sha:null},{path:'schema.sql',sha:null}]}
  ], releaseBlockers:['Live deployment unverified'], bookingEmail: {
    state:'disabled_by_business_decision', approvedProductionMode:'disabled',
    decision:{date:'2026-09-30',productionServiceExcludesBookingEmail:true,evidence:{path:'decision.md',sha}},
    productionModeEvidence:null,
    activationChecks:['bridge_review_and_merge','database_migrations','runtime_backlog_and_provider_uat','owner_send_approval']
      .map(id=>({id,description:id,status:'open',evidence:[]})),
  }};
  return {root,manifest,sha,data};
}
function observed(manifest, sha, mode='disabled') {
  manifest.bookingEmail.productionModeEvidence={
    mode,projectId:'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo',deploymentId:'dpl_ABC123',
    observedAt:'2026-09-30T11:00:00Z',source:'vercel_production_read_only',
    evidence:{path:'observed.md',sha},
  };
}
function ready(t) {
  const result=fixture(t);
  const {manifest,sha}=result;
  manifest.features[0]={id:'email',required:true,state:'present',artifacts:[{path:'proof.md',sha}]};
  manifest.releaseBlockers=[];
  return result;
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
  assert.match(check(root,manifest).join('\n'),/Historical evidence mismatch/);
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
test('A: documented business-disabled mode and attested production observation allow application release', t => {
  const {root,manifest}=ready(t);
  assert.deepEqual(check(root,manifest,true),[]);
  assert.ok(manifest.bookingEmail.activationChecks.every(item=>item.status==='open'));
});
test('B: missing or altered decision proof fails closed even if observed mode is disabled', t => {
  const {root,manifest}=ready(t);
  manifest.bookingEmail.decision.evidence.sha='0'.repeat(40);
  assert.match(check(root,manifest,true).join('\n'),/business decision evidence/);
  manifest.bookingEmail.decision.evidence=null;
  assert.match(check(root,manifest,true).join('\n'),/business decision evidence/);
});
test('C: send and capture both reject unresolved activation checks', t => {
  for (const mode of ['send','capture']) {
    const {root,manifest,sha}=ready(t);
    manifest.bookingEmail.state='activation_approved';
    manifest.bookingEmail.approvedProductionMode=mode;
    manifest.bookingEmail.decision.productionServiceExcludesBookingEmail=false;
    observed(manifest,sha,mode);
    assert.equal(check(root,manifest,true).filter(s=>s.startsWith('Booking email activation blocker')).length,4);
  }
});
test('D: active mode requires four individually resolved checks with intact evidence', t => {
  const {root,manifest,sha}=ready(t);
  manifest.bookingEmail.state='activation_approved';
  manifest.bookingEmail.approvedProductionMode='send';
  manifest.bookingEmail.decision.productionServiceExcludesBookingEmail=false;
  observed(manifest,sha,'send');
  for (const item of manifest.bookingEmail.activationChecks) {
    const path=item.id+'.md';
    writeFileSync(join(root,path),'Elfogadott UAT – történeti bizonyíték\n');
    item.status='resolved'; item.evidence=[{path,sha}];
  }
  assert.deepEqual(check(root,manifest,true),[]);
  manifest.bookingEmail.activationChecks[0].evidence[0].sha='0'.repeat(40);
  assert.match(check(root,manifest,true).join('\n'),/Activation evidence missing or changed/);
});
test('E: disabled mode does not require per-release Vercel runtime evidence', t => {
  const {root,manifest}=ready(t);
  manifest.bookingEmail.productionModeEvidence=null;
  assert.deepEqual(check(root,manifest,true),[]);
});
test('F: active mode still requires matching Vercel runtime evidence', t => {
  const {root,manifest}=ready(t);
  manifest.bookingEmail.state='activation_approved';
  manifest.bookingEmail.approvedProductionMode='send';
  manifest.bookingEmail.decision.productionServiceExcludesBookingEmail=false;
  assert.match(check(root,manifest,true).join('\n'),/Active production booking email mode missing, unknown, or different/);
});
