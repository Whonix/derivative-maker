#!/bin/bash

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

main() {
  prepare_environment
  install_source
  run_tests
}

prepare_environment() {
  ## We no longer use a default password of 'changeme', so there is no need
  ## to pipe it in here.
  sudo --non-interactive -- apt-get update -q
  sudo --non-interactive -- apt-get install --yes --no-install-recommends -- \
    git python3-behave python3-dogtail python3-pip python3-pyatspi
  gsettings set org.gnome.desktop.interface toolkit-accessibility true
}

install_source() {
  cd /home/user/
  git clone https://github.com/Mycobee/whonix_automated_test_suite.git
}

run_tests() {
  cd whonix_automated_test_suite
  DISPLAY=:0 xhost +
  NO_AT_BRIDGE=1 DISPLAY=:0 behave ./features
}

main
