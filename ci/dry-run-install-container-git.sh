#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Install git + ca-certificates inside the dry-run container.
## actions/checkout@v6 already pulled the source on the host; the
## helper-scripts submodule's git plumbing inside the container needs
## a working git binary to read .git/modules/* paths during build.
##
## Inputs:
##   $1 - container name to docker-exec into

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -ne 1 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <container-name>" >&2
   exit 64
fi

container_name="$1"

docker exec "${container_name}" apt-get update -qq
docker exec "${container_name}" apt-get install --yes --no-install-recommends -- \
   git ca-certificates
