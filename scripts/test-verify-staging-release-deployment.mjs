import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { matchingStagingDeployment } from './verify-staging-release-deployment.mjs';

const sha = 'a'.repeat(40);
const valid = { projectId: 'prj_LzVgZgZBCAj4zA64YoYED3XkLGKW', target: 'production', state: 'READY', meta: { githubCommitSha: sha, githubCommitRef: 'main' }, uid: 'dpl_example' };
test('accepts only READY main deployment of exact SHA in staging project', () => {
  assert.equal(matchingStagingDeployment({ deployments: [valid] }, sha), valid);
  for (const change of [
    { projectId: 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo' },
    { target: null }, { state: 'BUILDING' },
    { meta: { ...valid.meta, githubCommitRef: 'feature' } },
    { meta: { ...valid.meta, githubCommitSha: 'b'.repeat(40) } },
  ]) assert.equal(matchingStagingDeployment({ deployments: [{ ...valid, ...change }] }, sha), undefined);
  assert.throws(() => matchingStagingDeployment({}, sha), /Unexpected/);
});
