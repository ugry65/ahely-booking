import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { assertGitIsolated } from './check-production-git-isolation.mjs';
import { verifyProductionDeployment } from './verify-production-release-deployment.mjs';

const id = 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo';
const sha = 'a'.repeat(40);
const deployment = {
  id: 'dpl_abc123', projectId: id, target: 'production', readyState: 'READY',
  meta: { releaseCommitSha: sha, githubActionsRunId: '12345' },
};

test('Git isolation fails closed for connected, missing or wrong project', () => {
  assert.doesNotThrow(() => assertGitIsolated({ id, link: null }));
  assert.throws(() => assertGitIsolated({ id, link: { repo: 'ahely-booking' } }), /not proven/);
  assert.throws(() => assertGitIsolated({ id }), /not proven/);
  assert.throws(() => assertGitIsolated({ id: 'prj_other', link: null }), /Unexpected/);
});

test('production deployment records only expected project, commit and run', () => {
  assert.equal(verifyProductionDeployment(deployment, sha, '12345'), 'dpl_abc123');
  for (const changed of [
    { projectId: 'prj_other' }, { target: 'preview' }, { readyState: 'BUILDING' },
    { meta: { releaseCommitSha: 'b'.repeat(40), githubActionsRunId: '12345' } },
    { meta: { releaseCommitSha: sha, githubActionsRunId: '67890' } },
  ]) {
    assert.throws(() => verifyProductionDeployment({ ...deployment, ...changed }, sha, '12345'), /mismatch/);
  }
});
