const PROJECT_ID = 'prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo';

export function assertGitIsolated(project) {
  if (project?.id !== PROJECT_ID) throw new Error('Unexpected production Vercel project');
  // Vercel's project response includes link when a Git repository is connected.
  // Reject missing fields as well as a connected repository until the API response
  // has been checked against the actual project during the approved activation.
  if (!Object.hasOwn(project, 'link') || project.link !== null) {
    throw new Error('Production Git integration is not proven disconnected');
  }
}

if (process.argv[1]?.endsWith('/check-production-git-isolation.mjs')) {
  const { VERCEL_TOKEN: token, VERCEL_ORG_ID: team } = process.env;
  if (!token || !team) throw new Error('Missing Vercel release credentials');
  const url = new URL(`https://api.vercel.com/v9/projects/${PROJECT_ID}`);
  url.searchParams.set('teamId', team);
  const response = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`Project lookup failed: HTTP ${response.status}`);
  assertGitIsolated(await response.json());
  console.log('Production Vercel Git integration isolation verified.');
}
