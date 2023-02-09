#!/bin/bash

main() {
  prepare_environment
  install_source
  run_tests
}

prepare_environment() {
  dsudo setup-dist-noninteractive 1
  dsudo apt-get update -q
  dsudo apt-get install git python3-behave python3-pip python3-pyatspi python3-dogtail -yq --no-install-recommends
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
