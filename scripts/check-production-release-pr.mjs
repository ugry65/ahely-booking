import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const SHA = /^[0-9a-f]{40}$/;
const DEPLOYMENT = /^dpl_[A-Za-z0-9]+$/;
const UAT = /^https:\/\/github\.com\/ugry65\/ahely-booking\/(issues|pull)\/\d+(?:#issuecomment-\d+)?$/;

export function checkProductionReleasePr({ event, mainSha, mergedTree, headTree }) {
  const pr = event.pull_request;
  if (event.action === 'closed' || !pr || pr.base?.ref !== 'production' ||
      pr.head?.ref !== 'main' || pr.head?.repo?.full_name !== 'ugry65/ahely-booking' ||
      pr.base?.repo?.full_name !== 'ugry65/ahely-booking') {
    throw new Error('Release must be a same-repository main -> production pull request');
  }
  const releaseSha = pr.head.sha;
  if (!SHA.test(releaseSha) || mainSha !== releaseSha) {
    throw new Error('Release SHA must be the current main HEAD');
  }
  if (!SHA.test(mergedTree) || mergedTree !== headTree) {
    throw new Error('The production merge tree must exactly match the tested main tree');
  }
  const body = pr.body ?? '';
  const recordedSha = body.match(/^Release main SHA: `?([0-9a-f]{40})`?$/m)?.[1];
  const deploymentId = body.match(/^Staging deployment ID: `?(dpl_[A-Za-z0-9]+)`?$/m)?.[1];
  const uatUrl = body.match(/^Staging UAT: (\S+)$/m)?.[1];
  if (recordedSha !== releaseSha || !DEPLOYMENT.test(deploymentId ?? '') || !UAT.test(uatUrl ?? '')) {
    throw new Error('Record exact main SHA, staging deployment ID and GitHub UAT URL in the PR body');
  }
  return { releaseSha, deploymentId, uatUrl };
}

if (process.argv[1]?.endsWith('/check-production-release-pr.mjs')) {
  try {
    const git = (...args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
    const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    git('fetch', 'origin', 'main');
    const result = checkProductionReleasePr({
      event,
      mainSha: git('rev-parse', 'origin/main'),
      mergedTree: git('rev-parse', 'HEAD^{tree}'),
      headTree: git('rev-parse', `${event.pull_request?.head?.sha}^{tree}`),
    });
    console.log(`Release PR gate passed: main ${result.releaseSha}, staging ${result.deploymentId}, UAT ${result.uatUrl}`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
