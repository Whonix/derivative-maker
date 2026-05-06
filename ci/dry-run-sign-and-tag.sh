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

## Rely on the project's standard DEBFULLNAME / DEBEMAIL defaults
## from help-steps/variables (which signing-key-create also sources).
## The default email is descriptive enough that a leaked copy of this
## ephemeral cert is obvious (no real maintainer would ever sign with
## "derivative-distribution@local-signing.key"), so we don't override
## with a CI-specific identity.
: "${DEBFULLNAME:=derivative distribution auto generated local APT signing key}"
: "${DEBEMAIL:=derivative-distribution@local-signing.key}"
export DEBFULLNAME DEBEMAIL

## (1) Generate the ephemeral OpenPGP key. signing-key-create is
## idempotent on DEBEMAIL: re-runs are no-ops if a cert with that
## email already exists.
bash help-steps/signing-key-create

## (2) Read the cert fingerprint of the just-generated key. JSON +
## jq instead of awk-line-grep so a future change to sq's text layout
## (e.g. an extra header line) does not silently match the wrong
## field. Used as user.signingkey in git config below.
fpr=
fpr="$(sq cert list --cert-email "${DEBEMAIL}" --format json | jq -r '.[0].fingerprint')"
[ -n "${fpr}" ] || { printf '%s\n' "${BASH_SOURCE[0]}: failed to read CI cert fingerprint" >&2; exit 1; }
printf '%s\n' "${BASH_SOURCE[0]}: CI cert fingerprint: ${fpr}"

## (3) Export the armored cert and build the CI-only policy file.
## binary_build_folder_dist is set by help-steps/variables. Default
## to $HOME/derivative-binary if unset.
ci_cert_pem=
ci_cert_pem="$(mktemp)"
sq cert export --cert-email "${DEBEMAIL}" > "${ci_cert_pem}"

if [ -z "${binary_build_folder_dist:-}" ]; then
   binary_build_folder_dist="${HOME}/derivative-binary"
fi
mkdir --parents -- "${binary_build_folder_dist}"

ci_policy="${binary_build_folder_dist}/openpgp-policy.toml.ci"

## Initialize an empty policy scaffold (version + empty goodlist).
## sq-git policy authorize amends an existing policy file; it does
## not create one from scratch, so we seed the minimum it expects.
printf '%s\n' 'version = 0' 'commit_goodlist = []' > "${ci_policy}"

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

## Make the policy file readable by the unprivileged 'builder' user
## the dry-run drops to via help-steps/run-as-user. Without a+r the
## subsequent 'derivative-maker --dry-run' (running as builder) cannot
## open the policy file root just wrote, and git_sanity_test fails
## with a confusing 'permission denied' before sq-git is even reached.
chmod a+rX -- "${binary_build_folder_dist}"
chmod a+r  -- "${ci_policy}"

printf '%s\n' "${BASH_SOURCE[0]}: wrote CI policy to ${ci_policy}"

## (5) Configure git for sq-git-wrapper signing. Same wrapper the
## existing build uses for verification; reusing it keeps the trust
## tooling consistent.
git config user.signingkey "${fpr}"
git config gpg.format openpgp
git config gpg.openpgp.program "${PWD}/help-steps/sq-git-wrapper"
git config commit.gpgsign true
git config tag.gpgsign true
git config user.email "${DEBEMAIL}"
git config user.name "${DEBFULLNAME}"

## (6) Re-sign HEAD with the CI key. --amend --no-edit rewrites the
## tip without changing its content; -S forces a signature pass under
## the new gpg config.
git commit --amend --no-edit -S

## (7) Tag HEAD with an annotated signed tag. The dry-run targets
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

## (8) Print env exports for the workflow step to capture into
## subsequent docker exec calls. The workflow's next step does
## `docker exec --env sq_git_policy_file=... --env sq_git_trust_root=HEAD ...`
## using these values.
printf 'sq_git_policy_file=%s\n' "${ci_policy}"
printf 'sq_git_trust_root=HEAD\n'
