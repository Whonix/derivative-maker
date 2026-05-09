#!/bin/bash

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

readonly BUILD_LOG='/home/ansible/build.log'

## On a non-zero exit, dump the tail of /home/ansible/build.log to
## stderr. Ansible captures the script's stderr and surfaces it in
## the task output, so the actual build error becomes visible in the
## CI log without having to SSH back to the VPS to read build.log.
##
## Output is wrapped in GitHub Actions ::group::/::endgroup::
## workflow commands; even though this script runs on the VPS, the
## tokens propagate through ansible's stdout into the runner's log,
## where the Actions log viewer renders them as a collapsible block.
## Failure paths are noisy by definition - keeping the 200-line tail
## one click away (collapsed by default) keeps the surrounding log
## scannable.
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
  ## tee so build output is logged AND visible in the Ansible task
  ## output. pipefail so a non-zero exit from build_command
  ## propagates through the pipe.
  set -o pipefail
  build_command "$@" 2>&1 | tee --append -- "${BUILD_LOG}"
}

build_command() {
  /home/ansible/derivative-maker/help-steps/dm-build-official
}

main "$@"

true "$0: END"
