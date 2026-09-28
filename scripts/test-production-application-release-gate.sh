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
grep -Fq "not part of origin/main" "$file"
grep -Fq "intentionally fail-closed" "$file"

if grep -Eq 'vercel (deploy|--prod|promote)' "$file"; then
  echo "Production release workflow must remain non-deploying until activation prerequisites are approved." >&2
  exit 1
fi

echo "Production application release gate is fail-closed and non-deploying."
