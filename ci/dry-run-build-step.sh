#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Driver for the 'Drop privileges and run derivative-maker
## --dry-run true' workflow step. docker-execs into the running
## container and runs ci/dry-run-derivative-maker.sh.
##
## Forwards sq_git_policy_file via --env so help-steps/variables
## honors it (variables.bsh defaults sq_git_policy_file to
## ${source_code_folder_dist}/openpgp-policy.toml; the CI policy
## that authorizes the ephemeral key lives elsewhere - see
## ci/dry-run-sign-and-tag.sh). The path is fixed and predictable
## (matches binary_build_folder_dist's default for the 'builder'
## user inside the container), no need to discover it from the
## sign step's stdout.
##
## Inputs:
##   $1 - container name to docker-exec into.

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

docker exec \
   --env CI=true \
   --env sq_git_policy_file=/home/builder/derivative-binary/openpgp-policy.toml \
   "${container_name}" \
   ./ci/dry-run-derivative-maker.sh
