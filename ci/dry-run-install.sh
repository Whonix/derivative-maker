#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Install Debian apt dependencies for the dry-run workflow
## (.github/workflows/dry-run.yml).
##
## Container starts as root with a minimal Debian image. Use
## passwordless apt and skip Recommends to keep the layer thin. sudo
## is needed because help-steps/pre and several build steps invoke
## 'sudo --non-interactive' even in dry-run (cowbuilder probes etc.).
##
## Build deps: cowbuilder + mmdebstrap + debootstrap (the actual chroot
## creation tools the build steps drive).
##
## Runtime deps the build scripts assume are on PATH:
## - lsb-release: 'help-steps/variables' calls 'lsb_release --short
##   --id' to detect the host OS. debian:trixie does not ship it.
## - procps: 'helper-scripts/.../trace.bsh' calls 'ps' from its
##   backtrace path. debian:trixie does not ship it.
##
## TODO: deduplicate against buildconfig.d/30_dependencies.conf. The
## list of build deps overlaps with what
## build-steps.d/1200_prepare-build-machine consumes from
## $dist_build_script_build_dependency. Right shape for the fix:
## extract the apt-install logic from 1200_prepare-build-machine into
## a help-steps/install-build-deps helper that prepare-build-machine
## sources AND that this CI script calls. Sourcing 30_dependencies.conf
## directly from CI is messy (env-var dependencies, nounset traps),
## hence the inline list for now.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## CI guard. apt-get install on a developer host is dangerous.
## Refuse outside CI unless ALLOW_LOCAL=true is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

apt-get update -qq

apt-get install -y --no-install-recommends \
  bash sudo git ca-certificates \
  lsb-release procps \
  python3-yaml shellcheck file moreutils \
  cowbuilder mmdebstrap debootstrap
