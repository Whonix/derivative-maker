#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Driver for the 'Drop privileges and run derivative-maker
## --dry-run true' workflow step.
##
## Lives as a script (not inline in the workflow YAML) per
## agents/bash-style-guide.md: multi-line 'docker exec' with
## env-flag composition belongs in a shellcheck'd file. Lets a
## developer reproduce the exact CI invocation as
##   bash ci/dry-run-build-step.sh dryrun
## from a clone with sq_git_policy_file in the environment.
##
## Inputs:
##   $1 - container name to docker-exec into.
##
## Required environment:
##   sq_git_policy_file - absolute path inside the container to
##                        the CI policy file produced by
##                        ci/dry-run-sign-and-tag.sh.

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

if [ -z "${sq_git_policy_file:-}" ]; then
   printf '%s\n' "${BASH_SOURCE[0]}: sq_git_policy_file must be set (produced by ci/dry-run-sign-and-tag.sh)" >&2
   exit 1
fi

## sq_git_trust_root is NOT forwarded: help-steps/variables defaults
## it to "HEAD" for non-redistributable builds, which the dry-run is.
## Forwarding it would be redundant.
docker exec \
   --env CI=true \
   --env "sq_git_policy_file=${sq_git_policy_file}" \
   "${container_name}" \
   ./ci/dry-run-derivative-maker.sh
