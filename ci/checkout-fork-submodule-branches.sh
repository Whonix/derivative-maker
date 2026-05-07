#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## After parent-side submodule init from fork remotes (insteadOf
## rewrites in place via ci/configure-fork-mirror.sh), check out
## the matching branch in each submodule when one exists. Lets
## fork-side fixes flow into CI before they land upstream and get
## pinned: a PR on derivative-maker's claude/foo-bar branch can
## simultaneously test claude/foo-bar in helper-scripts and
## developer-meta-files, even though the parent's submodule SHA
## pins still point at the upstream-stable history.
##
## Caller contract:
##   - Pass the branch name to look for as the only argument
##     (typically ${{ github.head_ref || github.ref_name }} from
##     the workflow).
##   - Run from the parent repo's working tree.
##
## Behaviour:
##   - For each submodule listed in .gitmodules, try to fetch the
##     named branch from its origin. If the fetch succeeds and the
##     ref exists, checkout the fetched HEAD. If either fails, the
##     submodule keeps the SHA pin from the parent's index.
##   - All fetch/checkout failures are silently swallowed: a fork
##     without a matching branch is the common case, not an error.
##
## Reusable from a developer machine:
##   bash ci/checkout-fork-submodule-branches.sh my-feature-branch
## (run after 'bash ci/configure-fork-mirror.sh <fork-org>
##  && git submodule update --init --recursive')

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "$#" -ne 1 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <branch>" >&2
   exit 64
fi

branch=
branch="$1"

## Reject anything that wouldn't be a valid git ref name. Defends
## against accidental shell metachars from a workflow expression.
case "${branch}" in
   *[!a-zA-Z0-9._/-]*|"")
      printf '%s\n' "${BASH_SOURCE[0]}: refusing suspicious branch name: '${branch}'" >&2
      exit 64
      ;;
esac

## Iterate submodule paths from .gitmodules in plain bash. 'git
## submodule foreach' would require an embedded shell snippet as
## its argument; reading paths via 'git config --file .gitmodules
## --get-regexp' keeps each step a normal command in this script.
submodule_path=
while read -r _ submodule_path; do
   ## A submodule that hasn't been init'd has no .git dir/file.
   if [ ! -e "${submodule_path}/.git" ]; then
      continue
   fi

   if ! git -C "${submodule_path}" fetch --quiet origin "${branch}" 2>/dev/null; then
      ## Branch absent on the fork's remote - leave the SHA pin alone.
      continue
   fi

   if git -C "${submodule_path}" checkout --quiet "origin/${branch}" 2>/dev/null; then
      printf '%s: switched to origin/%s\n' "${submodule_path}" "${branch}"
   fi
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$')

printf '%s\n' "${BASH_SOURCE[0]}: done"
