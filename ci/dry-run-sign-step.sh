#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Driver for the 'Sign HEAD with ephemeral CI key' workflow step.
##
## Wraps three operations the workflow step needs:
##   1. docker exec into the running container as 'builder'.
##   2. Tee dry-run-sign-and-tag's stdout to a log file under
##      RUNNER_TEMP so the workflow can grep machine-readable env
##      exports out of it.
##   3. Forward the 'sq_git_policy_file=...' line to $GITHUB_ENV
##      via 'tee --append', not '>>', so the assignment is visible
##      in 'set -x' / actions step output rather than vanishing
##      into a redirection.
##
## Lives as a script (not inline in the workflow YAML) per
## agents/bash-style-guide.md: multi-line shell with pipes, tee,
## and grep belongs in a shellcheck'd file, not buried in a
## 'run: |' block. The script's CI=true guard rejects developer-
## machine invocations because it requires a running 'dryrun'
## container the workflow brought up.
##
## Inputs:
##   $1 - container name to docker-exec into.
##
## Required environment:
##   GITHUB_ENV  - workflow env file (set by GitHub Actions).
##   RUNNER_TEMP - workflow temp dir (set by GitHub Actions).

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "${CI:-}" != "true" ]; then
   printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true')." >&2
   exit 1
fi

if [ "$#" -ne 1 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <container-name>" >&2
   exit 64
fi

container_name=
container_name="$1"

log_file="${RUNNER_TEMP:?RUNNER_TEMP must be set}/sign-stdout.log"

## Run sign-and-tag as user 'builder' inside the container. The
## inner 'env CI=true' is required because run-as-user calls
## sudo --preserve-env=PATH which strips every other env var
## including the CI guard sign-and-tag itself checks.
docker exec --env CI=true "${container_name}" \
   ./help-steps/run-as-user --chown /work -- \
      builder env CI=true ./ci/dry-run-sign-and-tag.sh \
   | tee -- "${log_file}"

## Forward the policy-file path to the workflow env. The next
## step needs it as 'docker exec --env sq_git_policy_file=...'.
## sq_git_trust_root is NOT forwarded here: help-steps/variables
## already defaults it to "HEAD" for non-redistributable builds
## (which the dry-run is), so passing it would be redundant.
##
## 'tee --append' instead of '>>' makes the appended line visible
## in 'set -x' / actions step output, which is friendlier to
## debug than a silent redirection.
grep -E '^sq_git_policy_file=' -- "${log_file}" \
   | tee --append -- "${GITHUB_ENV}"
