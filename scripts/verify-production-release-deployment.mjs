const PROJECT_ID = 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo';

export function verifyProductionDeployment(deployment, sha, runId) {
  const id = deployment?.id ?? deployment?.uid;
  if (!/^dpl_[A-Za-z0-9]+$/.test(id ?? '') || deployment?.projectId !== PROJECT_ID ||
      deployment?.target !== 'production' || deployment?.readyState !== 'READY' ||
      deployment?.meta?.releaseCommitSha !== sha || deployment?.meta?.githubActionsRunId !== runId) {
    throw new Error('Production deployment identity, commit or READY status mismatch');
  }
  return id;
}

if (process.argv[1]?.endsWith('/verify-production-release-deployment.mjs')) {
  const { VERCEL_TOKEN: token, VERCEL_ORG_ID: team, REQUESTED_SHA: sha,
    DEPLOYMENT_URL: deploymentUrl, GITHUB_RUN_ID: runId, GITHUB_STEP_SUMMARY: summary,
    STAGING_UAT_EVIDENCE: uat } = process.env;
  if (!token || !team || !/^[0-9a-f]{40}$/.test(sha ?? '') ||
      !/^https:\/\/[a-zA-Z0-9.-]+\.vercel\.app$/.test(deploymentUrl ?? '') || !/^\d+$/.test(runId ?? '')) {
    throw new Error('Missing or invalid production deployment verification input');
  }
  const url = new URL(`https://api.vercel.com/v13/deployments/${new URL(deploymentUrl).hostname}`);
  url.searchParams.set('teamId', team);
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Deployment lookup failed: HTTP ${response.status}`);
  const id = verifyProductionDeployment(await response.json(), sha, runId);
  console.log(`Production deployment ${id} READY for release commit ${sha}`);
  if (summary) {
    const { appendFileSync } = await import('node:fs');
    appendFileSync(summary, `\n## Production application release\n- Commit: \`${sha}\`\n- Deployment: \`${id}\`\n- URL: ${deploymentUrl}\n- UAT: ${uat}\n- GitHub run: ${runId}\n- Actor: ${process.env.GITHUB_ACTOR}\n`);
  }
}
