#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Generate an ephemeral CI OpenPGP signing key, build an
## openpgp-policy.toml that authorizes that key on top of the
## upstream maintainer keys, re-sign HEAD with it, tag HEAD, and
## then delegate to ci/dry-run-resign-submodules.sh to re-sign
## each fork-branch-overlaid submodule HEAD with the same key so
## they all verify against the same policy.
##
## Why this exists:
##   The dry-run runs derivative-maker --dry-run which calls
##   git_sanity_test which calls sq_git_verify which is an
##   unconditional cryptographic trust gate. Three classes of
##   commits would otherwise fail at this gate:
##     * GitHub's auto-generated PR merge commit at HEAD - no
##       OpenPGP signature at all.
##     * Fork-side branch tips overlaid into submodules - SSH-
##       signed by the contributor's session key, but sq-git only
##       validates OpenPGP, so they look unsigned to it.
##     * Tags created during the build - need a signature from a
##       cert authorized for sign_tag in the policy.
##   Mint an ephemeral OpenPGP key, authorize it as
##   --project-maintainer in a CI policy file (seeded from the
##   project's openpgp-policy.toml so upstream maintainer keys
##   carry over for unmodified submodules), re-sign all of HEAD +
##   the new tag + each overlaid submodule HEAD with that key, and
##   point sq_git_policy_file at the CI policy. Every gate then
##   verifies against one consistent policy.
##
##   The key never leaves this container; the policy file lives in
##   the build-output folder for inspection but is not used outside
##   the dry-run.
##
## Why CI-only:
##   - Re-signs HEAD with --amend, rewriting the dev's local commit.
##   - Adds an annotated signed tag.
##   - Re-signs submodule HEADs the same way.
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

## DEBEMAIL: needed *after* signing-key-create returns. signing-key-
## create runs as a separate bash process that sources variables.bsh
## in its own subshell, so the default DEBEMAIL it picks for the
## ephemeral cert never reaches our shell. Two consumers below need
## to know it: (1) git config user.signingkey, which sq-git-wrapper
## reads to dispatch to 'sq sign --signer-email' (./help-steps/sq-
## git-wrapper rejects empty signing keys); (2) git config user.email
## so 'git commit --amend' has an author identity.
##
## The duplication of variables.bsh:1171's literal is annotated;
## a 'source ./help-steps/variables' would be cleaner but trips
## variables.bsh's own R-010 violations under nounset (unprotected
## ${dist_build_type_long} at line 537, etc.). The duplication is
## scheduled for removal once variables.bsh is fully ':-}-protected.
: "${DEBEMAIL:=derivative-distribution@local-signing.key}"
export DEBEMAIL

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

## (2) Export every cert in the keystore. On a fresh CI container the
## keystore has exactly one cert (the ephemeral one signing-key-
## create just minted), so '--all' picks it without us having to know
## the cert's email or fingerprint. Avoids the 'sq cert list --format
## json | jq' parse the trixie sq does not support and the awk grep
## the bash style guide rejects (R-010 / no parsing).
ci_cert_pem=
ci_cert_pem="$(mktemp)"
sq cert export --all > "${ci_cert_pem}"

if [ -z "${binary_build_folder_dist:-}" ]; then
   binary_build_folder_dist="${HOME}/derivative-binary"
fi
mkdir --parents -- "${binary_build_folder_dist}"

## (3) Build the CI policy file. Path is fixed (no '.ci' suffix) so
## downstream consumers (dry-run-build-step.sh, dry-run-derivative-
## maker.sh) and a developer running this script locally can compute
## the location without grepping the script's stdout. End goal is to
## upstream this script as help-steps/ci-sign-and-tag (or similar);
## the predictable path makes that natural.
##
## Seed from the project's existing openpgp-policy.toml so the
## upstream maintainer keys remain authorized for any submodule
## HEAD still at its canonical SHA pin. 'sq-git policy authorize'
## below adds our ephemeral CI key on top of those upstream
## authorizations, without removing them.
ci_policy="${binary_build_folder_dist}/openpgp-policy.toml"
project_policy="${PWD}/openpgp-policy.toml"
[ -r "${project_policy}" ] \
   || { printf '%s\n' "${BASH_SOURCE[0]}: missing project policy: ${project_policy}" >&2; exit 1; }
cp -- "${project_policy}" "${ci_policy}"

## (4) Authorize the CI cert in the policy via sq-git, instead of
## hand-rolling the [authorization."..."] TOML block. Keeps the
## policy file's exact shape (capability flag names, escaping of
## the user-id string, future schema bumps) the responsibility of
## sq-git rather than this script. --project-maintainer grants the
## full set (sign_commit, sign_tag, sign_archive, add_user,
## retire_user, audit) which is what the dry-run needs to walk the
## commit chain and authenticate any tag the build may inspect.
##
## NAME is just the policy-file label; it does NOT have to match
## the cert's userid. Use a fixed CI label so we don't have to
## know DEBFULLNAME in this shell.
sq-git policy authorize \
   --policy-file "${ci_policy}" \
   --project-maintainer \
   "ci-ephemeral-key" \
   "${ci_cert_pem}"
rm -f -- "${ci_cert_pem}"
printf '%s\n' "${BASH_SOURCE[0]}: wrote CI policy to ${ci_policy}"

## (5) Configure git for sq-git-wrapper signing. --global so the
## settings inherit into submodule git contexts (the per-submodule
## amend in ci/dry-run-resign-submodules.sh relies on this).
## user.signingkey is set to the email; sq-git-wrapper detects the
## '@' in it and dispatches to 'sq sign --signer-email' (see
## help-steps/sq-git-wrapper sign-mode dispatch).
git config --global user.signingkey "${DEBEMAIL}"
git config --global gpg.format openpgp
git config --global gpg.openpgp.program "${PWD}/help-steps/sq-git-wrapper"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global user.email "${DEBEMAIL}"

## (6) Re-sign HEAD with the CI key. --amend --no-edit rewrites the
## tip without changing its content; -S forces a signature pass
## under the new gpg config.
git commit --amend --no-edit -S

## Tag HEAD with an annotated signed tag. The dry-run targets may
## inspect the latest tag; having one present (and signed) is more
## realistic than using --allow-untagged. The tag name embeds the
## run id when set, otherwise the short SHA, so re-runs do not
## conflict. Hoisted out of a single-line ${VAR:-$(cmd)} form so
## the subshell is its own assignment (R-022 / bash-style-guide).
git_short_sha=
git_short_sha="$(git rev-parse --short HEAD)"
ci_tag_name="ci-dry-run-${GITHUB_RUN_ID:-${git_short_sha}}"
git tag -a -s -m 'CI dry-run ephemeral signed tag' "${ci_tag_name}"
printf '%s\n' "${BASH_SOURCE[0]}: tagged HEAD as ${ci_tag_name}"

## (7) Re-sign each fork-branch-overlaid submodule's HEAD. Walks
## the submodule tree in its own script; isolates the per-iteration
## state and keeps this driver linear.
./ci/dry-run-resign-submodules.sh
