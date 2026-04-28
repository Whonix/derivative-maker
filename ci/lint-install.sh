#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Install Debian apt dependencies for the lint workflow
## (.github/workflows/lint.yml).
##
## All linters come from Debian main:
##   shellcheck     - bash linting
##   python3-yaml   - workflow YAML parsing
##   file           - mime-type detection (used elsewhere in lint surface)
##   moreutils      - 'sponge' used by ci/local-checks.sh
##
## git + ca-certificates are needed by actions/checkout to work inside
## this container. sudo is needed by help-steps/variables: it runs
## '$SUDO_TO_ROOT rm ...' at source time and falls back to
## 'sudo --non-interactive' if SUDO_TO_ROOT is unset; minimal Debian
## Docker images lack sudo.
##
## Runnable locally too (e.g. inside a podman container) for parity
## with CI.

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

cat -- /etc/os-release

apt-get update

apt-get install -y --no-install-recommends \
  bash git ca-certificates sudo \
  shellcheck \
  python3-yaml file moreutils
