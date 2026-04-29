#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Parse every workflow file under .github/workflows/ via
## 'python3 -c "import yaml; yaml.safe_load(...)"'. Fails closed if
## tooling or workflow files are missing - both are environment bugs
## that should be visible, not silently skipped.
##
## Runs in CI as the 'yaml workflow files' step of lint.yml.
## Standalone-runnable via 'bash ci/lint-yaml.sh'.

set -o nounset
set -o errtrace
set -o pipefail
## NOT errexit: if one file fails linting, other files should still be
## checked.

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 2

shopt -s nullglob
yaml_files=( .github/workflows/*.yml .github/workflows/*.yaml )
shopt -u nullglob

if (( ${#yaml_files[@]} == 0 )); then
  printf '::error::%s\n' 'no workflow files in .github/workflows/ - environment bug' >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf '::error::%s\n' 'python3 not available - environment bug; install python3-yaml' >&2
  exit 1
fi
if ! python3 -c 'import yaml' 2>/dev/null; then
  printf '::error::%s\n' 'python3 -c "import yaml" failed - install python3-yaml' >&2
  exit 1
fi

rc=0
for yml in "${yaml_files[@]}"; do
  if python3 -c \
      'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' \
      "$yml" 2>/dev/null; then
    printf '[ OK ] %s\n' "$yml"
  else
    printf '::error::yaml parse failed: %s\n' "$yml" >&2
    rc=1
  fi
done

if (( rc == 0 )); then
  printf '\nPASSED: yaml on %d workflow file(s)\n' "${#yaml_files[@]}"
fi
exit "$rc"
