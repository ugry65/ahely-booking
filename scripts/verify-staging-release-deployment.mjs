const STAGING_PROJECT_ID = 'prj_LzVgZgZBCAj4zA64YoYED3XkLGKW';

export function matchingStagingDeployment(payload, sha) {
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error('Invalid release SHA');
  if (!Array.isArray(payload?.deployments)) throw new Error('Unexpected Vercel deployment response');
  return payload.deployments.find((deployment) =>
    deployment.projectId === STAGING_PROJECT_ID &&
    deployment.target === 'production' &&
    deployment.readyState === 'READY' &&
    deployment.meta?.githubCommitSha === sha &&
    deployment.meta?.githubCommitRef === 'main'
  );
}

if (process.argv[1]?.endsWith('/verify-staging-release-deployment.mjs')) {
  const { VERCEL_TOKEN: token, VERCEL_ORG_ID: team, REQUESTED_SHA: sha } = process.env;
  if (!token || !team || !/^[0-9a-f]{40}$/.test(sha ?? '')) {
    throw new Error('Missing Vercel credentials or invalid release SHA');
  }
  const url = new URL('https://api.vercel.com/v6/deployments');
  url.searchParams.set('projectId', STAGING_PROJECT_ID);
  url.searchParams.set('teamId', team);
  url.searchParams.set('target', 'production');
  url.searchParams.set('limit', '100');
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Staging deployment lookup failed: HTTP ${response.status}`);
  const deployment = matchingStagingDeployment(await response.json(), sha);
  if (!deployment) throw new Error('No READY main staging deployment for the release SHA');
  const id = deployment.uid ?? deployment.id;
  if (!/^dpl_[A-Za-z0-9]+$/.test(id ?? '')) throw new Error('Missing staging deployment ID');
  console.log(`Verified staging deployment ${id} for ${sha}`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const { appendFileSync } = await import('node:fs');
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n- Staging deployment: \`${id}\`\n- Verified SHA: \`${sha}\`\n`);
  }
}
