#!/usr/bin/env bash
set -euo pipefail

file=".github/workflows/production-application-release.yml"

grep -Fq "workflow_dispatch:" "$file"
grep -Fq "default: dry-run" "$file"
grep -Fq "DEPLOY-PRODUCTION" "$file"
grep -Fq "environment: Production – ahely-booking" "$file"
grep -Fq "github.ref == 'refs/heads/main'" "$file"
grep -Fq "github.actor == 'ugry65'" "$file"
grep -Fq "Verify actual staging Vercel deployment" "$file"
grep -Fq "prj_ZW7nVAOcYPjttZtES2iHoeA8iOTo" "$file"
grep -Fq "yasrmxwjojepessivhmc" "$file"
grep -Fq "https://foglalas.a-hely.com" "$file"
grep -Fq 'check-production-preview-scope.mjs' "$file"
grep -Fq 'git rev-parse origin/main)" != "$REQUESTED_SHA"' "$file"
grep -Fq "must be the current main HEAD" "$file"
grep -Fq 'check-production-git-isolation.mjs' "$file"
grep -Fq 'vercel build --prod' "$file"
grep -Fq 'vercel deploy --prebuilt --prod' "$file"
grep -Fq 'verify-production-release-deployment.mjs' "$file"
grep -Fq 'releaseCommitSha=$REQUESTED_SHA' "$file"

echo "Production application release gate is manual, SHA-bound and Git-isolation guarded."
