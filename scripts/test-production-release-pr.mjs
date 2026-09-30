import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkProductionReleasePr } from './check-production-release-pr.mjs';

const sha = 'a'.repeat(40);
const tree = 'b'.repeat(40);
const event = {
  action: 'synchronize',
  pull_request: {
    head: { ref: 'main', sha, repo: { full_name: 'ugry65/ahely-booking' } },
    base: { ref: 'production', repo: { full_name: 'ugry65/ahely-booking' } },
    body: `Release main SHA: \`${sha}\`\nStaging deployment ID: \`dpl_ABC123\`\nStaging UAT: https://github.com/ugry65/ahely-booking/issues/241`,
  },
};
const input = { event, mainSha: sha, mergedTree: tree, headTree: tree };

test('accepts a matching main release with UAT evidence and identical merge tree', () => {
  assert.deepEqual(checkProductionReleasePr(input), {
    releaseSha: sha, deploymentId: 'dpl_ABC123', uatUrl: 'https://github.com/ugry65/ahely-booking/issues/241',
  });
});

test('fails closed on wrong source, changed main, wrong tree or missing UAT evidence', () => {
  for (const candidate of [
    { ...input, event: { ...event, pull_request: { ...event.pull_request, head: { ...event.pull_request.head, ref: 'feature' } } } },
    { ...input, mainSha: 'c'.repeat(40) },
    { ...input, mergedTree: 'd'.repeat(40) },
    { ...input, event: { ...event, pull_request: { ...event.pull_request, body: '' } } },
  ]) assert.throws(() => checkProductionReleasePr(candidate));
});
