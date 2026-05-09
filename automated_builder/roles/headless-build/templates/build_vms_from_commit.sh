#!/bin/bash

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

true "$0: START"

export CI=true

main() {
  set -o pipefail
  build_command "$@" 2>&1 | tee -a /home/ansible/build.log
}

build_command() {
  /home/ansible/derivative-maker/help-steps/dm-build-official \
    --allow-untagged true \
    --remote-derivative-packages true
}

main "$@"

true "$0: END"
