import { readFileSync, existsSync } from 'node:fs';
import { resolve, relative, isAbsolute } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export function check(root, manifest, release = false) {
  const errors = [];
  const fail = message => errors.push(message);
  const hash = path => {
    if (typeof path !== 'string' || !path || isAbsolute(path) ||
        relative(root, resolve(root, path)).startsWith('..')) throw new Error('Unsafe artifact path');
    const full = resolve(root, path);
    if (!existsSync(full)) return null;
    const bytes = readFileSync(full);
    return createHash('sha1').update(Buffer.from('blob ' + bytes.length + '\0')).update(bytes).digest('hex');
  };
  if (manifest.version !== 2 || !Array.isArray(manifest.evidence) || !manifest.evidence.length ||
      !Array.isArray(manifest.features) || !manifest.features.length ||
      !Array.isArray(manifest.releaseBlockers)) throw new Error('Invalid evidence manifest');
  const email = manifest.bookingEmail;
  const requiredChecks = ['bridge_review_and_merge', 'database_migrations', 'runtime_backlog_and_provider_uat', 'owner_send_approval'];
  if (!email || !['disabled_by_business_decision', 'activation_approved'].includes(email.state) ||
      !['disabled', 'capture', 'send'].includes(email.approvedProductionMode) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(email.decision?.date ?? '') ||
      email.decision?.productionServiceExcludesBookingEmail !== (email.state === 'disabled_by_business_decision') ||
      !Array.isArray(email.activationChecks) ||
      email.activationChecks.map(item => item.id).sort().join(',') !== requiredChecks.sort().join(',')) {
    throw new Error('Invalid booking email release policy');
  }
  if ((email.state === 'disabled_by_business_decision') !== (email.approvedProductionMode === 'disabled')) {
    throw new Error('Booking email policy and approved production mode disagree');
  }
  const proof = (item, label) => {
    if (!item || !/^[a-f0-9]{40}$/.test(item.sha ?? '') || hash(item.path) !== item.sha) fail(label);
  };
  proof(email.decision?.evidence, 'Booking email business decision evidence missing or changed');
  const resolvedPaths = new Set();
  for (const item of email.activationChecks) {
    if (typeof item.description !== 'string' || !item.description ||
        !['open', 'resolved'].includes(item.status) || !Array.isArray(item.evidence)) {
      throw new Error('Invalid booking email activation check: ' + item.id);
    }
    if (item.status === 'resolved' && !item.evidence.length) fail('Activation check lacks proof: ' + item.id);
    for (const evidence of item.evidence) {
      proof(evidence, 'Activation evidence missing or changed: ' + item.id);
      if (item.status === 'resolved') {
        if (resolvedPaths.has(evidence.path) || evidence.path === email.decision?.evidence?.path) {
          fail('Activation checks require distinct decision and readiness evidence: ' + item.id);
        }
        resolvedPaths.add(evidence.path);
      }
    }
  }
  for (const item of manifest.evidence) {
    if (!/^[a-f0-9]{40}$/.test(item.sha) || hash(item.path) !== item.sha) fail('Historical evidence mismatch: ' + item.path);
  }
  for (const feature of manifest.features) {
    if (!['present', 'absent'].includes(feature.state) || typeof feature.required !== 'boolean' ||
        !Array.isArray(feature.artifacts) || !feature.artifacts.length) throw new Error('Invalid feature: ' + feature.id);
    for (const item of feature.artifacts) {
      if ((feature.state === 'absent' && item.sha !== null) ||
          (feature.state === 'present' && !/^[a-f0-9]{40}$/.test(item.sha))) throw new Error('Invalid artifact state: ' + item.path);
      if (hash(item.path) !== item.sha) fail('Code/evidence drift: ' + feature.id + ': ' + item.path);
    }
    if (release && feature.required && feature.state !== 'present') fail('Required feature missing: ' + feature.id);
  }
  if (release) {
    for (const blocker of manifest.releaseBlockers) fail('Release blocker: ' + blocker);
    // Disabled booking email is an explicit business policy, not a per-release runtime gate.
    // Runtime Vercel evidence becomes mandatory only when booking email is activated.
    if (email.approvedProductionMode !== 'disabled') {
      const observed = email.productionModeEvidence;
      if (!observed || !['capture', 'send'].includes(observed.mode) ||
          observed.mode !== email.approvedProductionMode ||
          observed.projectId !== 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo' ||
          !/^dpl_[A-Za-z0-9]+$/.test(observed.deploymentId ?? '') ||
          !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(observed.observedAt ?? '') ||
          observed.source !== 'vercel_production_read_only') {
        fail('Active production booking email mode missing, unknown, or different from approved mode');
      } else {
        proof(observed.evidence, 'Production booking email mode evidence missing or changed');
        if (observed.evidence?.path === email.decision?.evidence?.path || resolvedPaths.has(observed.evidence?.path)) {
          fail('Production mode observation requires its own evidence');
        }
      }
      for (const item of email.activationChecks) {
        if (item.status !== 'resolved' || !item.evidence.length) fail('Booking email activation blocker: ' + item.id);
      }
    }
  }
  return errors;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.some(arg => arg !== '--release')) throw new Error('Usage: node scripts/check-release-evidence.mjs [--release]');
    const manifest = JSON.parse(readFileSync('docs/release-evidence.json', 'utf8'));
    const errors = check(process.cwd(), manifest, args.includes('--release'));
    if (errors.length) {
      console.error(errors.join('\n'));
      process.exitCode = 1;
    } else console.log(args.includes('--release') ? 'Recorded release gates satisfied; verify the attested Vercel mode against the live deployment before approval.' : 'Evidence consistent. This is NOT production readiness approval.');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
