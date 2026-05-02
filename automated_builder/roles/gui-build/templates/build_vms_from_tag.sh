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
on_exit() {
  local rc=$?
  if [ "${rc}" -ne 0 ] && [ -r "${BUILD_LOG}" ]; then
    printf '%s\n' \
      "" \
      "=== build_vms_from_tag.sh: failed (rc=${rc}). Tail of '${BUILD_LOG}': ===" >&2
    tail --lines=200 -- "${BUILD_LOG}" >&2 || true
    printf '%s\n' '=== end of build.log tail ===' >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT

true "$0: START"

export CI=true

main() {
  ## Use 'tee' so build output is both logged to file and visible in the
  ## Ansible task output. Previously all output was silently redirected,
  ## making CI failures opaque ("non-zero return code" with no details).
  ## Using 'pipefail' so a non-zero exit from build_command propagates
  ## through the pipe.
  set -o pipefail
  build_command "$@" 2>&1 | tee --append -- "${BUILD_LOG}"
}

build_command() {
  /home/ansible/derivative-maker/help-steps/dm-build-official
}

main "$@"

true "$0: END"
