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
  if (manifest.version !== 1 || !Array.isArray(manifest.evidence) || !manifest.evidence.length ||
      !Array.isArray(manifest.features) || !manifest.features.length ||
      !Array.isArray(manifest.releaseBlockers)) throw new Error('Invalid evidence manifest');
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
  if (release) for (const blocker of manifest.releaseBlockers) fail('Release blocker: ' + blocker);
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
    } else console.log(args.includes('--release') ? 'Recorded release gates satisfied; live evidence still requires review.' : 'Evidence consistent. This is NOT production readiness approval.');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
