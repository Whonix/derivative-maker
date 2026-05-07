#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## After parent-side 'git submodule update --init', rewrite each
## submodule's origin remote URL from its canonical Kicksecure/* or
## Whonix/* upstream to the corresponding fork-org mirror.
##
## Two-arg API: separate mirrors per upstream. derivative-maker's
## submodules straddle two upstream orgs (Kicksecure for the
## hardening-distribution side, Whonix for the gateway/workstation
## side). A single-org mirror like org-ai-assisted/* collapses both
## into one namespace - in that case pass the same arg twice. A
## forker who maintains separate Kicksecure-mirror and Whonix-mirror
## orgs passes them distinctly. Either layout falls out of two
## positional args.
##
## Why this approach instead of git's url.<base>.insteadOf:
##   --local insteadOf in the parent's .git/config rewrites the
##   network endpoint only when the *parent's* git context issues
##   the command. 'git submodule update' clones via the rewrite,
##   but each submodule's own .git/config records the canonical
##   URL. A later in-submodule 'git fetch origin <branch>' executes
##   in the submodule's git context, where the parent's local
##   rewrite is invisible - so the fetch hits the canonical host
##   and 404s on any fork-only branch. Direct 'remote set-url'
##   avoids that layering surprise: the per-submodule URL is the
##   source of truth, no rewrite needed.
##
## Caller contract:
##   - Run after 'git submodule update --init --recursive' so each
##     submodule's .git/config exists.
##   - Pass <kicksecure-mirror-org> and <whonix-mirror-org>. Same
##     value twice for the single-org case.
##   - Each mirror org must contain every Kicksecure/* (resp.
##     Whonix/*) submodule this parent reaches.
##
## Reusable from a developer machine:
##   git submodule update --init --recursive
##   bash ci/configure-fork-mirror.sh org-ai-assisted org-ai-assisted
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

   ## Rewrite Kicksecure/<name> -> ${kicksecure_mirror}/<name> and
   ## Whonix/<name> -> ${whonix_mirror}/<name>. Anything else (e.g.
   ## third-party submodules) is left alone.
   case "${old_url}" in
      https://github.com/Kicksecure/*)
         new_url="https://github.com/${kicksecure_mirror}/${old_url#https://github.com/Kicksecure/}"
         ;;
      https://github.com/Whonix/*)
         new_url="https://github.com/${whonix_mirror}/${old_url#https://github.com/Whonix/}"
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
