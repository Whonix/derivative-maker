#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Install global git url.<fork>.insteadOf rewrites so URLs targeting
## the upstream Kicksecure/* and Whonix/* orgs resolve to the
## corresponding fork-org mirrors instead. derivative-maker's
## submodules straddle two upstream orgs, so two rewrites cover
## every cross-org submodule the build reaches; adding new ones
## requires no further config.
##
## Two-arg API: <kicksecure-mirror> <whonix-mirror>. A forker who
## keeps separate Kicksecure-mirror and Whonix-mirror orgs passes
## them distinctly. The single-org case (org-ai-assisted/* mirrors
## both) passes the same value twice. Each mirror org must contain
## every Kicksecure/* (resp. Whonix/*) repo this parent reaches.
##
## --global, not --local: a parent-repo --local insteadOf rewrites
## only operations issued by the parent's git context. 'git
## submodule update --init' clones via the rewrite, but each
## submodule's own git context (used by a later 'git -C <submodule>
## fetch origin <branch>') would not see the parent's --local
## config, leaving fetches to hit the canonical host. --global is
## loaded by every git process - parent and submodule alike - so
## the rewrite applies uniformly.
##
## Trade-off: --global writes to ~/.gitconfig. On an ephemeral CI
## runner this is harmless (runner is destroyed at end of job).
## On a developer machine the rewrite persists across all repos
## until manually undone with
##   git config --global --unset-all url.https://github.com/<fork>/.insteadOf
## (one line per fork-org). Documented here so the cleanup step is
## discoverable.
##
## Reusable from a developer machine:
##   bash ci/configure-fork-mirror.sh org-ai-assisted org-ai-assisted
##   git submodule update --init --recursive
##   bash ci/checkout-fork-submodule-branches.sh my-feature-branch

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "$#" -ne 2 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <kicksecure-mirror-org> <whonix-mirror-org>" >&2
   exit 64
fi

kicksecure_mirror=
whonix_mirror=
kicksecure_mirror="$1"
whonix_mirror="$2"

case "${kicksecure_mirror}" in
   *[!a-zA-Z0-9_.-]*|"")
      printf '%s\n' "${BASH_SOURCE[0]}: refusing suspicious kicksecure-mirror org: '${kicksecure_mirror}'" >&2
      exit 64
      ;;
esac
case "${whonix_mirror}" in
   *[!a-zA-Z0-9_.-]*|"")
      printf '%s\n' "${BASH_SOURCE[0]}: refusing suspicious whonix-mirror org: '${whonix_mirror}'" >&2
      exit 64
      ;;
esac

## When kicksecure_mirror == whonix_mirror (the single-org case),
## both rewrites land under the same git config key
## ('url.https://github.com/<fork>/.insteadOf'). git config without
## --add overwrites the existing value, so the second 'git config'
## would clobber the first - only the Whonix->fork rewrite would
## survive and Kicksecure/* clones would still go to canonical
## hosts. --add appends a second value under the same key, and
## insteadOf accepts multiple values per key (any URL matching any
## of them gets rewritten). For the two-org case (different
## mirrors), the keys differ, so --add is harmless.
git config --global \
   "url.https://github.com/${kicksecure_mirror}/.insteadOf" \
   "https://github.com/Kicksecure/"

git config --global --add \
   "url.https://github.com/${whonix_mirror}/.insteadOf" \
   "https://github.com/Whonix/"

printf '%s: rewrote Kicksecure/ -> %s/, Whonix/ -> %s/\n' \
   "${BASH_SOURCE[0]}" "${kicksecure_mirror}" "${whonix_mirror}"
