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
##   (e.g. AI-pushed commits with commit.gpgsign=false) would
##   otherwise fail at this gate. Generating an ephemeral key,
##   trust-rooting it in a CI-only policy file, and re-signing
##   HEAD with it lets the gate pass without weakening the
##   real-build trust model.
##
##   The key never leaves this container; the policy file lives in
##   the build-output folder for inspection but is not used outside
##   the dry-run.
##
## Why CI-only:
##   - Generates an OpenPGP key under DEBEMAIL=ci@dryrun.local that
##     would clash with a developer's real key.
##   - Re-signs HEAD with --amend, rewriting the dev's local commit.
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

## Ephemeral CI identity. Picked to be obviously non-real so a leaked
## copy of this cert can't masquerade as a maintainer.
export DEBEMAIL='ci@dryrun.local'
export DEBFULLNAME='CI Dry-Run Builder'

## (1) Generate the ephemeral OpenPGP key. signing-key-create is
## idempotent on DEBEMAIL: re-runs are no-ops if a cert with that
## email already exists.
bash help-steps/signing-key-create

## (2) Read the cert fingerprint of the just-generated key. Used as
## user.signingkey in git config below.
fpr="$(sq cert list --cert-email "$DEBEMAIL" \
       | awk '/Fingerprint:/ {print $2; exit}')"
[ -n "${fpr}" ] || { printf '%s\n' "${BASH_SOURCE[0]}: failed to read CI cert fingerprint" >&2; exit 1; }
printf '%s\n' "${BASH_SOURCE[0]}: CI cert fingerprint: ${fpr}"

## (3) Export the armored cert and build the CI-only policy file.
ci_cert_pem="$(mktemp)"
sq cert export --cert-email "$DEBEMAIL" > "${ci_cert_pem}"

## binary_build_folder_dist is set by help-steps/variables. Source
## it for the value; if unset, default to $HOME/derivative-binary.
if [ -z "${binary_build_folder_dist:-}" ]; then
   binary_build_folder_dist="${HOME}/derivative-binary"
fi
mkdir --parents -- "${binary_build_folder_dist}"
ci_policy="${binary_build_folder_dist}/openpgp-policy.toml.ci"
{
  printf 'version = 0\n'
  printf 'commit_goodlist = []\n\n'
  printf '[authorization."%s <%s>"]\n' "$DEBFULLNAME" "$DEBEMAIL"
  printf 'sign_commit = true\n'
  printf 'sign_tag = true\n'
  printf 'sign_archive = true\n'
  printf 'add_user = true\n'
  printf 'retire_user = true\n'
  printf 'audit = true\n'
  printf 'keyring = """\n'
  cat -- "${ci_cert_pem}"
  printf '"""\n'
} > "${ci_policy}"
rm -f -- "${ci_cert_pem}"
printf '%s\n' "${BASH_SOURCE[0]}: wrote CI policy to ${ci_policy}"

## (4) Configure git for sq-git-wrapper signing. Same wrapper the
## existing build uses for verification; reusing it keeps the trust
## tooling consistent.
git config user.signingkey "${fpr}"
git config gpg.format openpgp
git config gpg.openpgp.program "$PWD/help-steps/sq-git-wrapper"
git config commit.gpgsign true
git config tag.gpgsign true
git config user.email "$DEBEMAIL"
git config user.name "$DEBFULLNAME"

## (5) Re-sign HEAD with the CI key. --amend --no-edit rewrites the
## tip without changing its content; -S forces a signature pass under
## the new gpg config.
git commit --amend --no-edit -S

## (6) Tag HEAD with an annotated signed tag. The dry-run targets
## may inspect the latest tag; having one present (and signed) is
## more realistic than using --allow-untagged. The tag name embeds
## the run id when set, otherwise the short SHA, so re-runs do not
## conflict.
ci_tag_name="ci-dry-run-${GITHUB_RUN_ID:-$(git rev-parse --short HEAD)}"
git tag -a -s -m 'CI dry-run ephemeral signed tag' "${ci_tag_name}"
printf '%s\n' "${BASH_SOURCE[0]}: tagged HEAD as ${ci_tag_name}"

## (7) Print env exports for the workflow step to capture into
## subsequent docker exec calls. The workflow's next step does
## `docker exec --env sq_git_policy_file=... --env sq_git_trust_root=HEAD ...`
## using these values.
printf 'sq_git_policy_file=%s\n' "${ci_policy}"
printf 'sq_git_trust_root=HEAD\n'
