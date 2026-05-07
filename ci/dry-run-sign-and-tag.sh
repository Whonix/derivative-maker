#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Generate an ephemeral CI OpenPGP signing key, build a CI-only
## openpgp-policy.toml.ci that trust-roots that key, re-sign HEAD
## with it, and tag HEAD with a signed annotated tag. Caller is
## expected to export
##   sq_git_policy_file=<path-to-this-policy>
##   sq_git_trust_root=HEAD
## before invoking derivative-maker --dry-run so sq-git
## verification authenticates the chain.
##
## Why this exists:
##   The dry-run runs derivative-maker --dry-run which calls
##   git_sanity_test which calls sq_git_verify which is an
##   unconditional cryptographic trust gate. Unsigned commits
##   (e.g. AI-pushed commits with commit.gpgsign=false) and
##   GitHub's auto-generated PR merge commits (signed by GitHub
##   Actions, not by an authorized developer key) would otherwise
##   fail at this gate. Generating an ephemeral key, trust-rooting
##   it in a CI-only policy file via sq-git policy authorize, and
##   re-signing HEAD with it lets the gate pass without weakening
##   the real-build trust model.
##
##   The key never leaves this container; the policy file lives in
##   the build-output folder for inspection but is not used outside
##   the dry-run.
##
## Why CI-only:
##   - Re-signs HEAD with --amend, rewriting the dev's local commit.
##   - Adds an annotated signed tag.
##   Refuse outside CI unless ALLOW_LOCAL=true is set explicitly.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ "${CI:-}" != "true" ] && [ "${ALLOW_LOCAL:-}" != "true" ]; then
   printf '%s\n' "${BASH_SOURCE[0]}: refusing to run outside CI (CI != 'true'). Set ALLOW_LOCAL=true to override." >&2
   exit 1
fi

cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.."

## Mirror help-steps/variables's DEBFULLNAME / DEBEMAIL fallbacks
## (lines ~1168-1172). The signing-key-create call below sources
## variables.bsh in its own subshell to mint the ephemeral cert
## with these values; we set them in our parent shell so the
## subsequent 'sq cert export --cert-email "${DEBEMAIL}"' knows
## what email to query.
##
## Why duplicate the literals instead of 'source ./help-steps/variables'
## here: variables.bsh has unprotected '${var}' derefs of vars
## normally set by parse-cmd (e.g. dist_build_type_long at line 537,
## R-010 violations from before nounset-hardening) that abort under
## set -o nounset when sourced from a non-build context. Pre-setting
## every required var would be more brittle than mirroring two
## defaults; once variables.bsh is fully ':-}-protected, this block
## can be replaced with the source.
: "${DEBFULLNAME:=derivative distribution auto generated local APT signing key}"
: "${DEBEMAIL:=derivative-distribution@local-signing.key}"
export DEBFULLNAME DEBEMAIL

## (1) Generate the ephemeral OpenPGP key. signing-key-create is
## idempotent on DEBEMAIL: re-runs are no-ops if a cert with that
## email already exists.
##
## This script is expected to run as the unprivileged 'builder' user
## the dry-run drops to via help-steps/run-as-user (the workflow
## wraps it accordingly). signing-key-create's pre-flight rejects
## root invocations to protect a developer's real signing keys, so
## running as builder is also what keeps that gate happy without
## resorting to the dist_build_allow_root=true escape hatch.
./help-steps/signing-key-create

## (2) Export the armored cert. binary_build_folder_dist is set by
## help-steps/variables; default to $HOME/derivative-binary if unset.
##
## We deliberately do NOT extract the fingerprint here. sq-git policy
## authorize accepts a cert FILE as its positional argument
## (synopsis: 'sq-git policy authorize NAME FILE|FINGERPRINT|KEYID'),
## and sq-git-wrapper resolves a signing identity that contains '@'
## as --signer-email, so 'git config user.signingkey "${DEBEMAIL}"'
## is enough for the signing path. This avoids parsing 'sq cert list'
## output entirely (no JSON flag in the trixie sq, no awk grep).
ci_cert_pem=
ci_cert_pem="$(mktemp)"
sq cert export --cert-email "${DEBEMAIL}" > "${ci_cert_pem}"

if [ -z "${binary_build_folder_dist:-}" ]; then
   binary_build_folder_dist="${HOME}/derivative-binary"
fi
mkdir --parents -- "${binary_build_folder_dist}"

ci_policy="${binary_build_folder_dist}/openpgp-policy.toml.ci"

## Seed from the project's existing openpgp-policy.toml so the
## upstream maintainer keys remain authorized for the submodule
## verification paths (git_sanity_test --mode all also walks
## submodules; a from-scratch policy that only trusts the CI key
## would reject every submodule HEAD signed by a real maintainer
## with 'Key <FPR> missing'). 'sq-git policy authorize' below adds
## our ephemeral CI key on top of those upstream authorizations,
## without removing them.
project_policy="${PWD}/openpgp-policy.toml"
[ -r "${project_policy}" ] \
   || { printf '%s\n' "${BASH_SOURCE[0]}: missing project policy: ${project_policy}" >&2; exit 1; }
cp -- "${project_policy}" "${ci_policy}"

## (4) Authorize the CI cert in the policy via sq-git, instead of
## hand-rolling the [authorization."..."] TOML block. Keeps the policy
## file's exact shape (capability flag names, escaping of the user-id
## string, future schema bumps) the responsibility of sq-git rather
## than this script. --project-maintainer grants the full set
## (sign_commit, sign_tag, sign_archive, add_user, retire_user,
## audit) which is what the dry-run needs to walk the commit chain
## and authenticate any tag the build may inspect.
sq-git policy authorize \
   --policy-file "${ci_policy}" \
   --project-maintainer \
   "${DEBFULLNAME} <${DEBEMAIL}>" \
   "${ci_cert_pem}"
rm -f -- "${ci_cert_pem}"
printf '%s\n' "${BASH_SOURCE[0]}: wrote CI policy to ${ci_policy}"

## (4) Configure git for sq-git-wrapper signing. Same wrapper the
## existing build uses for verification; reusing it keeps the trust
## tooling consistent.
##
## user.signingkey is set to the email; sq-git-wrapper detects the
## '@' in it and dispatches to 'sq sign --signer-email' (see
## help-steps/sq-git-wrapper sign-mode dispatch).
git config user.signingkey "${DEBEMAIL}"
git config gpg.format openpgp
git config gpg.openpgp.program "${PWD}/help-steps/sq-git-wrapper"
git config commit.gpgsign true
git config tag.gpgsign true
git config user.email "${DEBEMAIL}"
git config user.name "${DEBFULLNAME}"

## (5) Re-sign HEAD with the CI key. --amend --no-edit rewrites the
## tip without changing its content; -S forces a signature pass under
## the new gpg config.
git commit --amend --no-edit -S

## (6) Tag HEAD with an annotated signed tag. The dry-run targets
## may inspect the latest tag; having one present (and signed) is
## more realistic than using --allow-untagged. The tag name embeds
## the run id when set, otherwise the short SHA, so re-runs do not
## conflict. Hoisted out of a single-line ${VAR:-$(cmd)} form so the
## subshell is its own assignment (R-022 / bash-style-guide).
git_short_sha=
git_short_sha="$(git rev-parse --short HEAD)"
ci_tag_name="ci-dry-run-${GITHUB_RUN_ID:-${git_short_sha}}"
git tag -a -s -m 'CI dry-run ephemeral signed tag' "${ci_tag_name}"
printf '%s\n' "${BASH_SOURCE[0]}: tagged HEAD as ${ci_tag_name}"

## (7) Goodlist any submodule HEAD that has been switched off its
## SHA pin (i.e. that the workflow's checkout-fork-submodule-
## branches.sh step repointed at a fork branch). The fork branch
## tip is signed by an unrelated developer key, not by any cert in
## our policy, so sq-git --mode submodules would otherwise reject
## it. 'sq-git policy goodlist' adds the SHA to the policy's
## commit_goodlist - those commits are then trusted regardless of
## signature, scoped to this CI policy file only. Submodules still
## at their canonical pin are left alone (their HEAD is signed by
## an upstream maintainer, already authorized in the seeded
## policy).
##
## 'git submodule status' prefixes:
##   ' ' (space) - HEAD matches the index pin
##   '+'         - HEAD differs from the index pin
##   '-'         - submodule not initialized (we filter those out
##                 - the fork-mirror init step has already run)
##   'U'         - merge conflict
## The case-glob below matches the '+' lines.
submodule_status_line=
submodule_sha=
submodule_path_rest=
submodule_path=
while read -r submodule_status_line; do
   case "${submodule_status_line}" in
      +*) ;;
      *) continue ;;
   esac

   ## Strip leading '+', then split off SHA and path. Format:
   ##   '+<sha> <path> (<describe>)'
   submodule_sha="${submodule_status_line#+}"
   submodule_path_rest="${submodule_sha#* }"
   submodule_sha="${submodule_sha%% *}"
   submodule_path="${submodule_path_rest%% *}"

   case "${submodule_sha}" in
      [0-9a-f]*) ;;
      *)
         printf '%s: skipping non-SHA status line: %s\n' "${BASH_SOURCE[0]}" "${submodule_status_line}" >&2
         continue
         ;;
   esac

   ## sq-git policy goodlist resolves the SHA against the CWD's git
   ## repository. The submodule's HEAD SHA only exists in the
   ## submodule's git db, not the parent's, so the call has to run
   ## with the submodule as CWD - otherwise sq-git aborts with
   ## "revspec '<sha>' not found". Subshell + cd scopes the cwd
   ## change to this single command.
   (
      cd -- "${submodule_path}"
      sq-git policy goodlist \
         --policy-file "${ci_policy}" \
         -- "${submodule_sha}"
   )
   printf '%s: goodlisted %s (%s)\n' "${BASH_SOURCE[0]}" "${submodule_sha}" "${submodule_path}"
done < <(git submodule status --recursive)

## (8) Print env exports for the workflow step to capture into
## subsequent docker exec calls. The workflow's next step does
## `docker exec --env sq_git_policy_file=... --env sq_git_trust_root=HEAD ...`
## using these values.
printf 'sq_git_policy_file=%s\n' "${ci_policy}"
printf 'sq_git_trust_root=HEAD\n'
