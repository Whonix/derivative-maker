#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## After parent-side 'git submodule update --init', rewrite each
## submodule's origin remote URL from its canonical Kicksecure/* or
## Whonix/* upstream to the same-named repo under ${fork_org}/. Each
## submodule's own .git/config now explicitly points at the fork
## remote, so any subsequent git operation inside the submodule's
## context (a 'git fetch' for a fork branch, an in-submodule
## 'git pull') reaches the right host.
##
## Why this approach instead of git's url.<base>.insteadOf:
##   --local insteadOf in the parent's .git/config rewrites the
##   network endpoint only when the *parent's* git context issues a
##   command. 'git submodule update' clones via the rewrite, but
##   each submodule's own .git/config records the canonical URL.
##   A later 'git -C <submodule> fetch origin <branch>' executes in
##   the submodule's git context, where the parent's local rewrite
##   is invisible - so the fetch hits the canonical host and 404s
##   on any fork-only branch. Direct 'remote set-url' avoids that
##   layering surprise: the per-submodule URL is the source of
##   truth, no rewrite needed.
##
## Why this lives separately from ci/checkout-fork-submodule-branches.sh:
##   This script writes config; that one walks branches and
##   checkouts. Pairing them in one workflow run is the common
##   path, but a developer might want one without the other (e.g.
##   "rewrite URLs but stay on the SHA pin" for offline reproduction).
##
## Caller contract:
##   - Pass the fork org name as the only argument.
##   - Run after 'git submodule update --init --recursive' so
##     each submodule's .git/config exists and is mutable.
##   - The fork must mirror every Kicksecure/* and Whonix/* repo
##     this parent's submodules reach.
##
## Reusable from a developer machine:
##   git submodule update --init --recursive
##   bash ci/configure-fork-mirror.sh org-ai-assisted
##   bash ci/checkout-fork-submodule-branches.sh my-feature-branch

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

submodule_path=
old_url=
new_url=
while read -r _ submodule_path; do
   if [ ! -e "${submodule_path}/.git" ]; then
      printf 'skip   %s: not initialized\n' "${submodule_path}"
      continue
   fi

   old_url="$(git -C "${submodule_path}" remote get-url origin 2>/dev/null || printf '')"
   if [ -z "${old_url}" ]; then
      printf 'skip   %s: no origin remote configured\n' "${submodule_path}"
      continue
   fi

   ## Rewrite Kicksecure/<name> or Whonix/<name> to ${fork_org}/<name>.
   ## Anything else (e.g. third-party submodules) is left alone.
   case "${old_url}" in
      https://github.com/Kicksecure/*)
         new_url="https://github.com/${fork_org}/${old_url#https://github.com/Kicksecure/}"
         ;;
      https://github.com/Whonix/*)
         new_url="https://github.com/${fork_org}/${old_url#https://github.com/Whonix/}"
         ;;
      *)
         printf 'leave  %s: not Kicksecure/* or Whonix/* (origin: %s)\n' "${submodule_path}" "${old_url}"
         continue
         ;;
   esac

   git -C "${submodule_path}" remote set-url origin "${new_url}"
   printf 'rewrite %s: %s -> %s\n' "${submodule_path}" "${old_url}" "${new_url}"
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$')

printf '%s\n' "${BASH_SOURCE[0]}: done"
