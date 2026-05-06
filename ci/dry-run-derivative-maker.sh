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
## --unsupported-os true: ubuntu-latest's 'debian:trixie' container
## *should* identify as trixie and pass the OS sanity check, but
## the flag protects the workflow from an unexpected codename detected
## by a build step computing it from apt sources.
##
## A plain 'timeout' wraps the call to ensure this doesn't hang. The
## workflow timeout should also prevent this.
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

## help-steps/run-as-user invokes 'sudo --preserve-env=PATH ...' to
## drop privileges, which strips every env var except PATH (and the
## inline user_name= assignment). The sq_git_* env vars set by the
## workflow's 'Sign HEAD with ephemeral CI key' step are visible here
## (docker exec --env), but won't survive the sudo unless we inline
## them as 'env VAR=val' arguments AFTER 'builder' so they end up in
## the builder shell's environment. Required by help-steps/variables
## (which honors a pre-set sq_git_policy_file) and by
## help-steps/git_sanity_test (which dies if sq_git_policy_file is
## empty).
timeout 1200 \
  ./help-steps/run-as-user --chown "$PWD" -- \
    builder \
    env "sq_git_policy_file=${sq_git_policy_file:-}" \
        "sq_git_trust_root=${sq_git_trust_root:-}" \
    ./derivative-maker \
      --dry-run true \
      --unsupported-os true \
      --allow-uncommitted true \
      --allow-untagged true \
      --flavor source \
      --target source
