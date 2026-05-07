#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Driver for the 'Sign HEAD with ephemeral CI key' workflow step.
## docker-execs into the running container as 'builder' and runs
## ci/dry-run-sign-and-tag.sh, which writes the CI policy file at
## a fixed path under ${binary_build_folder_dist}/openpgp-policy.toml.
##
## Lives as a script (not inline in the workflow YAML) per
## agents/bash-style-guide.md: docker exec composition + run-as-user
## indirection belongs in a shellcheck'd file.
##
## The output policy path is fixed and predictable, so this script
## does not need to capture sign-and-tag's stdout, grep for env
## exports, or write to $GITHUB_ENV - the next workflow step
## composes the path from the same convention.
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

## The inner 'env CI=true' is required because run-as-user calls
## sudo --preserve-env=PATH which strips every other env var
## including the CI guard sign-and-tag itself checks.
docker exec --env CI=true "${container_name}" \
   ./help-steps/run-as-user --chown /work -- \
   builder env CI=true ./ci/dry-run-sign-and-tag.sh
