#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Configure git url.<fork>.insteadOf rewrites so submodule URLs
## targeting the upstream Kicksecure/ and Whonix/ orgs resolve to
## ${fork_org}/<repo>.git instead.
##
## Why this exists:
##   derivative-maker's submodules cross two upstream orgs:
##   Kicksecure/<repo> (helper-scripts, genmkfile, ...) and
##   Whonix/<repo> (whonix-firewall, kloak, ...). Relative submodule
##   URLs ('url = ../helper-scripts' in .gitmodules) cannot satisfy
##   both at once, and absolute URLs nail the canonical org into
##   .gitmodules - bad for forkers who mirror the whole org-graph
##   into a single namespace (e.g. org-ai-assisted/*).
##
##   git's url.X.insteadOf rewrite is the standard way out: keep
##   .gitmodules canonical, and let each fork rewrite both upstream
##   bases to its own org via two 'git config' lines. Submodule SHA
##   pins still govern which commit is checked out; only the remote
##   URL changes.
##
## Caller contract:
##   - Run from the parent repo's working tree (this script writes
##     to ./.git/config via 'git config --local').
##   - Pass the fork org name as the only argument.
##   - The fork must mirror every Kicksecure/* and Whonix/* repo
##     this parent's submodules reach; otherwise 'git submodule
##     update' will 404 on the missing mirror.
##
## Idempotent:
##   git config without --add overwrites the existing value. We use
##   --add for the second rewrite so both are recorded; rerunning
##   the script appends duplicates. 'git config --unset-all url.X.
##   insteadOf' before the writes keeps repeated runs clean.
##
## Reusable from a developer machine, not just CI:
##   bash ci/configure-fork-mirror.sh org-ai-assisted
##   git submodule sync --recursive
##   git submodule update --init --recursive

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "$#" -ne 1 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <fork-org-name>" >&2
   exit 64
fi

fork_org=
fork_org="$1"

case "${fork_org}" in
   *[!a-zA-Z0-9_.-]*|"")
      printf '%s\n' "${BASH_SOURCE[0]}: refusing suspicious org name: '${fork_org}'" >&2
      exit 64
      ;;
esac

base=
base="https://github.com/${fork_org}/"

## Drop any prior rewrites for this base so re-runs do not append
## stale values.
git config --local --unset-all "url.${base}.insteadOf" 2>/dev/null || true

git config --local "url.${base}.insteadOf" "https://github.com/Kicksecure/"
git config --local --add "url.${base}.insteadOf" "https://github.com/Whonix/"

printf '%s\n' "${BASH_SOURCE[0]}: rewrites configured: Kicksecure/, Whonix/ -> ${fork_org}/"
