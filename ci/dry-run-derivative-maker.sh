#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Drive the dry-run smoke build for .github/workflows/dry-run.yml.
##
## help-steps/run-as-user creates a 'builder' user with passwordless
## sudo, chowns the source tree, and execs the given command as that
## user. This satisfies sanity-tests' "source must not be owned by
## root" check while still letting the build steps that need sudo
## (cowbuilder, mkdir under /var/cache/pbuilder) work.
##
## --unsupported-os true: ubuntu-latest's 'debian:bookworm' container
## *should* identify as bookworm and pass the OS sanity check, but
## the flag protects the workflow from an unexpected codename detected
## by a build step computing it from apt sources.
##
## A plain 'timeout' wraps the call as belt-and-suspenders for a step
## that misses the workflow timeout (e.g. signal-trapping subprocess).
##
## Standalone-runnable: from a checked-out source tree with
## /usr/libexec/helper-scripts symlinked and the apt deps installed
## (see ci/dry-run-install.sh), 'bash ci/dry-run-derivative-maker.sh'
## reproduces what CI does.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## CI guard. Provisions a 'builder' user via run-as-user and chowns
## the source tree - surprising on a developer host. Refuse outside
## CI unless ALLOW_LOCAL=true is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.."

timeout 1200 \
  ./help-steps/run-as-user --chown "$PWD" builder -- \
    ./derivative-maker \
      --dry-run true \
      --unsupported-os true \
      --allow-uncommitted true \
      --allow-untagged true \
      --flavor source \
      --target source
