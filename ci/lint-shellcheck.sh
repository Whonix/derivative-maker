#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## shellcheck on the full bash tree.
##
## The codebase is shellcheck-clean at --severity=warning thanks to
## 604ca7b "Bash error-handling and idiomatic-bash overhaul". This
## script bumps severity to 'info' and excludes three codes that the
## codebase consciously triggers as a style choice:
##
##   SC2086  Double quote to prevent globbing/word splitting
##           Many call sites intentionally word-split on string
##           variables that contain space-separated option lists
##           (e.g. '$apt_unattended_opts', '$pids' in umount_kill.sh,
##           'eval $cmd_string' in pre's retry dispatch). Refactoring
##           each into an array is sound but invasive; out of scope
##           here.
##   SC2317  Command appears to be unreachable
##           False positive in the build-step dispatch pattern: each
##           build-steps.d/* file defines functions called via the
##           file's own bottom-of-file dispatcher, which shellcheck
##           cannot see statically.
##   SC2016  Expressions don't expand in single quotes
##           Triggered by intentional literal-'$1' arguments to
##           --customize-hook in help-steps/mmdebstrap and 'bash -c'
##           recursive calls in help-steps/git_sanity_test. Single
##           quoting is correct in those contexts.
##
## Real findings (e.g. SC2162 'read without -r', genuinely missing
## quotes) are still surfaced. shellcheck also internally runs
## 'bash -n' on every file, so a separate bash_n check is redundant.
##
## Runs in CI as the 'shellcheck' step of lint.yml. Standalone-runnable
## via 'bash ci/lint-shellcheck.sh'.

set -o nounset
set -o errtrace
set -o pipefail
## NOT errexit: if one file fails linting, other files should still be
## checked.

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 2

if ! command -v shellcheck >/dev/null 2>&1; then
  printf '::error::%s\n' 'shellcheck not installed - environment bug; apt-get install shellcheck' >&2
  exit 1
fi

## File list: '*.sh' / '*.bsh' extensions plus extensionless files
## with a bash shebang in known directories, plus the top-level entry
## scripts. Submodules are intentionally skipped: each is its own
## project.
shellcheck_files=()
while IFS= read -r -d '' f; do
  shellcheck_files+=( "$f" )
done < <(find . -type f \( -name '*.sh' -o -name '*.bsh' \) \
           -not -path './.git/*' -not -path './packages/*' -print0 2>/dev/null)
while IFS= read -r -d '' f; do
  first_line=""
  IFS= read -r first_line < "$f" 2>/dev/null || first_line=""
  case "$first_line" in
    '#!/bin/bash'*|'#!/usr/bin/env bash'*) shellcheck_files+=( "$f" ) ;;
  esac
done < <(find help-steps build-steps.d automated_builder ci \
           -type f ! -name '*.sh' ! -name '*.bsh' ! -path '*/.*' \
           -print0 2>/dev/null)
for f in derivative-maker derivative-update; do
  [ -f "$f" ] && shellcheck_files+=( "$f" )
done

if (( ${#shellcheck_files[@]} == 0 )); then
  printf '::error::%s\n' 'no bash files found for shellcheck - environment bug' >&2
  exit 1
fi

if shellcheck --severity=info --exclude=SC2086,SC2317,SC2016 \
     --shell=bash "${shellcheck_files[@]}"; then
  printf '\nPASSED: shellcheck on %d files\n' "${#shellcheck_files[@]}"
  exit 0
fi
printf '::error::shellcheck failed on at least one of %d files\n' "${#shellcheck_files[@]}" >&2
exit 1
