#!/bin/bash

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

readonly BUILD_LOG='/home/ansible/build.log'

## On non-zero exit, dump the build.log tail to stderr. Ansible
## captures the script's stderr and surfaces it in the task output,
## so the actual build error is visible in the CI log without an
## SSH back to the VPS.
##
## Wrap in GitHub Actions ::group::/::endgroup:: tokens; they
## propagate through ansible's stdout to the runner log, where the
## Actions viewer renders the tail as a collapsible block.
on_exit() {
  local rc=$?
  if [ "${rc}" -ne 0 ] && [ -r "${BUILD_LOG}" ]; then
    printf '%s\n' "::group::build.log tail (rc=${rc})" >&2
    printf '%s\n' "=== Tail of '${BUILD_LOG}' (last 200 lines) ===" >&2
    tail --lines=200 -- "${BUILD_LOG}" >&2 || true
    printf '%s\n' '=== end of build.log tail ===' >&2
    printf '%s\n' '::endgroup::' >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT

true "$0: START"

export CI=true

main() {
  set -o pipefail
  build_command "$@" 2>&1 | tee --append -- "${BUILD_LOG}"
}

build_command() {
  /home/ansible/derivative-maker/help-steps/dm-build-official
}

main "$@"

true "$0: END"
