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

## Compute the path to the CI policy file from builder's home dir
## via getent (matches binary_build_folder_dist's default in
## help-steps/variables when run as builder). Avoids a literal
## '/home/builder/' string and survives a future user.add elsewhere
## that picked a non-/home prefix. Single ': '-delimited field
## extraction is standard Unix, not awk.
builder_home=
builder_home="$(getent passwd builder | cut -d: -f6)"

## help-steps/run-as-user invokes 'sudo --preserve-env=PATH ...' to
## drop privileges, which strips every env var except PATH (and the
## inline user_name= assignment). sq_git_policy_file has to be
## re-inlined as an 'env VAR=val' argument after 'builder' so it
## ends up in the builder shell's environment.
##
## sq_git_trust_root is NOT forwarded: help-steps/variables defaults
## it to "HEAD" for non-redistributable builds (the dry-run is one).
timeout 1200 \
  ./help-steps/run-as-user --chown "$PWD" -- \
    builder \
    env "sq_git_policy_file=${builder_home}/derivative-binary/openpgp-policy.toml" \
    ./derivative-maker \
      --dry-run true \
      --unsupported-os true \
      --allow-uncommitted true \
      --allow-untagged true \
      --flavor source \
      --target source
