#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Dump environment context so a CI failure later in the run is
## diagnosable without log auth. Output uses '::group::' GitHub
## Actions workflow commands so the lines collapse on the run page.
##
## Runs in the lint workflow ('.github/workflows/lint.yml') after
## checkout + submodule init. Standalone-runnable locally for
## reproducing what CI sees.

set -o nounset
set -o errtrace
set -o pipefail
## NOT errexit: every diagnostic block is best-effort. A missing
## tool or unreadable directory should not abort subsequent dumps.

## CI guard. The ::group:: workflow commands are CI-shaped output.
## Refuse outside CI unless ALLOW_LOCAL=true is set explicitly.
if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
  printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
  exit 1
fi

printf '%s\n' "::group::pwd / id / debian version"
pwd
id
cat -- /etc/os-release || true
printf '%s\n' "::endgroup::"

printf '%s\n' "::group::ls top-level"
ls -la
printf '%s\n' "::endgroup::"

printf '%s\n' "::group::git submodule status"
git submodule status || true
printf '%s\n' "::endgroup::"

printf '%s\n' "::group::ls packages/kicksecure/helper-scripts"
ls -la -- packages/kicksecure/helper-scripts/ || true
printf '%s\n' "::endgroup::"

printf '%s\n' "::group::tool versions"
shellcheck --version || true
python3 --version || true
printf '%s\n' "::endgroup::"
