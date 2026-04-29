#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Run every offline lint check in sequence, the same set that the
## CI lint workflow runs as separate steps. Use this for one-shot
## local pre-commit-style coverage.
##
##   bash ci/local-checks.sh    # run all
##
## CI invokes the per-step scripts directly so failures are attributed
## to the right step in the GitHub Actions UI:
##   ci/lint-yaml.sh
##   ci/lint-shellcheck.sh
##
## Why no other checks: bash_n is redundant with shellcheck;
## actionlint is not packaged in Debian (see
## agents/github-actions-security.md); regression and variables_smoke
## are obsolete - the deprecated tokens are gone, and dry-run.yml
## supersedes the smoke test.

set -o nounset
set -o errtrace
set -o pipefail
## NOT errexit: if one test fails, other tests should still be run.

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 2

rc=0
bash ci/lint-yaml.sh       || rc=$?
printf '\n'
bash ci/lint-shellcheck.sh || rc=$?

if (( rc != 0 )); then
  printf '\nFAILED\n' >&2
fi
exit "$rc"
