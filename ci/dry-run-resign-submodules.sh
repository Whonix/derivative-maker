#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Walk every submodule whose HEAD has been switched off its SHA pin
## (the workflow's checkout-fork-submodule-branches.sh step) and
## re-sign each HEAD with the parent's signing key (set up by
## ci/dry-run-sign-and-tag.sh as --global git config). The fork
## branch tips are SSH-signed by the contributor's session key, but
## sq-git only validates OpenPGP, so they look unsigned to it and
## would fail submodule verification.
##
## Re-signing is preferred over the previous goodlist-the-SHA
## approach because the resulting commit is genuinely signed by a
## cert in the policy - matches how a real maintainer-signed commit
## flows, no commit_goodlist policy hack required.
##
## 'git submodule status' prefixes:
##   ' ' (space) - HEAD matches the index pin
##   '+'         - HEAD differs from the index pin (= fork-branch
##                 overlay applied)
##   '-'         - submodule not initialized
##   'U'         - merge conflict
## We amend on '+' lines. Pin-stable submodules are left alone:
## their HEAD is already signed by an upstream maintainer cert
## that ci/dry-run-sign-and-tag.sh keeps authorized in the seeded
## CI policy.
##
## Lives in its own script so the resign loop is self-contained
## (avoids the 'while read' over process substitution inside
## sign-and-tag.sh, and the per-iteration cd-subshell). The
## per-submodule pushd/popd here keeps the cwd state local to one
## iteration without forking a subshell.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

submodule_status_line=
submodule_path_rest=
submodule_path=
git submodule status --recursive | while read -r submodule_status_line; do
   case "${submodule_status_line}" in
      +*) ;;
      *) continue ;;
   esac

   ## Format: '+<sha> <path> (<describe>)' - we want the path field.
   submodule_path_rest="${submodule_status_line#+* }"
   submodule_path="${submodule_path_rest%% *}"

   ## --global git config from sign-and-tag.sh means signing
   ## settings carry into the submodule's git context; no
   ## per-submodule git config needed.
   pushd -- "${submodule_path}" >/dev/null
   git commit --amend --no-edit -S
   popd >/dev/null

   printf '%s: re-signed submodule HEAD: %s\n' "${BASH_SOURCE[0]}" "${submodule_path}"
done
