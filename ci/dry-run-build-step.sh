#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Driver for the 'Drop privileges and run derivative-maker
## --dry-run true' workflow step. docker-execs into the running
## container and runs ci/dry-run-derivative-maker.sh.
##
## sq_git_policy_file is NOT forwarded across docker exec - the
## inner script computes the path itself from getent passwd builder
## so we avoid a hardcoded '/home/builder/' literal at the host
## boundary.
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

docker exec --env CI=true "${container_name}" \
   ./ci/dry-run-derivative-maker.sh
