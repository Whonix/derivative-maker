#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## Local smoke-test harness for derivative-maker.
##
## Runs 'help-steps/dm-build-official --dry-run true' against the current
## git checkout, as a non-root user with passwordless sudo, without
## provisioning a DigitalOcean droplet via Ansible (unlike
## 'scripts/run_automated_builder.sh').
##
## Goal: catch parse-cmd / variables / early build-step regressions on a
## developer machine before pushing to CI. '--dry-run true' per
## 'help-steps/parse-cmd' is specifically for exercising
## 'dm-prepare-release' against placeholder artifacts (empty sparse raw
## image, auto-generated signing keys in '~/.signify', ...).
##
## The user/sudoers/chown plumbing is delegated to the reusable
## 'help-steps/run-as-user'; this script's responsibility is the
## test-specific bits: defaults for flavor / arch, '--dry-run true'
## itself, narrowing 'flavors_list' to a single flavor, and pre-setting
## the env vars that 'help-steps/variables' (and friends) need before
## parse-cmd has run.
##
## Host OS:
## - 'build-steps.d/1100_sanity-tests' hard-checks
##   'VERSION_CODENAME == $dist_build_apt_stable_release' (Debian
##   'trixie' at time of writing), so this script assumes it runs on
##   Debian trixie. On non-trixie hosts, use the existing
##   containerised path instead:
##     sudo ./docker/derivative-maker-docker-run -- --dry-run true \\
##         --allow-untagged true --flavor kicksecure-cli \\
##         --arch amd64 --target virtualbox
##
## Usage:
##   sudo automated_builder/scripts/run_local_dry_run.sh \
##       [--flavor kicksecure-cli] [--arch amd64] \
##       [--build-user ubuntu] [--source-dir /path/to/derivative-maker] \
##       [-- <extra args passed through to dm-build-official>]

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

die() {
   printf '%s\n' "ERROR: $*" >&2
   exit 1
}

if ! [ "${CI:-}" = "true" ]; then
   die "$0: Run only inside CI!"
fi

## Defaults.
##
## 'dm-build-official-one' builds every flavor in '$flavors_list' with
## both '--target virtualbox' and '--target qcow2' (per architecture,
## see the 'case $architecture' block in 'help-steps/dm-build-official-one').
## The harness narrows this to a single flavor so the smoke test finishes
## in reasonable time; override with --flavor if you want another.
flavor="kicksecure-cli"
architecture="amd64"
build_user="ubuntu"
source_dir=""

passthrough_args=()
while [ "$#" -gt 0 ]; do
   case "$1" in
      --flavor)       flavor="$2";      shift 2 ;;
      --arch)         architecture="$2"; shift 2 ;;
      --build-user)   build_user="$2";  shift 2 ;;
      --source-dir)   source_dir="$2";  shift 2 ;;
      --)             shift; passthrough_args+=("$@"); break ;;
      -h|--help)
         sed -n '/^##/{s/^## \{0,1\}//;p}' -- "$0"
         exit 0
         ;;
      *) die "unknown argument: '$1' (use '--' to pass args to dm-build-official)" ;;
   esac
done

if [ -z "$source_dir" ]; then
   ## Default to the parent git tree of this script.
   source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
[ -d "$source_dir/.git" ] || die "source_dir '$source_dir' is not a git checkout"
[ -x "$source_dir/help-steps/dm-build-official" ] || \
   die "'$source_dir/help-steps/dm-build-official' not found / not executable"

run_as_user="$source_dir/help-steps/run-as-user"
[ -x "$run_as_user" ] || die "'$run_as_user' not found / not executable"

## {{ ensure submodules are present. The build-steps read files inside
## 'packages/kicksecure/helper-scripts' and other submodules; an
## uninitialised submodule presents as an empty directory and trips
## '1100_sanity-tests' + 'source pre'.
##
## We do this BEFORE handing off to 'help-steps/run-as-user' because
## the chown there needs git's submodule clones to already exist; and
## we do it as root because at this point the source_dir might still
## be owned by root (the chown happens inside run-as-user). Once
## 'run-as-user' has chowned, subsequent submodule operations from
## inside the build itself run as the build user.
if ! test -r "$source_dir/packages/kicksecure/helper-scripts/usr/libexec/helper-scripts/pre_bsh.bsh" \
    && ! test -r "$source_dir/packages/kicksecure/helper-scripts/usr/libexec/helper-scripts/log_run_die.sh" ; then
   git -C "$source_dir" submodule update --init --recursive --jobs 20 --depth 1
fi
## }}

## {{ run the build.
## - '--dry-run true' asks parse-cmd to inject 'build_dry_run=true'.
## - '--allow-untagged true' bypasses the "not on a tagged commit"
##   sanity test; a dev branch is typically not tagged.
## - 'dm-build-official-one' reads '$flavors_list' from the environment
##   if set, otherwise it expands to its full list (6 flavors); we
##   narrow it to '$flavor' and pass '$architecture' as
##   'dist_build_target_arch' (the same env var that 'parse-cmd'
##   writes from '--arch').
## - 'CI' is deliberately left unset so 'parse-cmd' does not override
##   'build_dry_run' and so 'dm-build-official' does not call
##   'derivative-update --update-only' (which re-fetches submodules
##   and runs git signature verification -- out of scope for a local
##   smoke test).
##
## 'help-steps/run-as-user' handles: 'useradd' if missing, atomic
## sudoers drop-in via visudo+sponge, 'chown -R' of the source tree,
## and the final 'sudo -u' handoff. We just supply the env, command
## and args.
##
## bash can't export arrays, but a scalar env var expands under
## '"${var[@]}"' as a one-element array, which is exactly what we want
## for narrowing '$flavors_list' to a single flavor.
"$run_as_user" --chown "$source_dir" \
   -- \
   "$build_user" \
   env \
      HOME="/home/$build_user" \
      USER="$build_user" \
      LOGNAME="$build_user" \
      user_name="$build_user" \
      dist_build_target_arch="$architecture" \
      flavors_list="$flavor" \
      build_dry_run="true" \
   bash -c "
      cd -- '$source_dir'
      ./help-steps/dm-build-official \
         --dry-run true \
         --allow-untagged true \
         ${passthrough_args[*]@Q}
   "
## }}
