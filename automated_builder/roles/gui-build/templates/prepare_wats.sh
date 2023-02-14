#!/bin/bash

main() {
  prepare_environment
  install_source
}

prepare_environment() {
  dsudo apt-get update -q
  dsudo apt-get install git python3-behave python3-pip python3-pyatspi python3-dogtail -yq --no-install-recommends
  dsudo -E -u user gsettings set org.gnome.desktop.interface toolkit-accessibility true
}

install_source() {
  cd /home/user/
  git clone https://github.com/Mycobee/whonix_automated_test_suite.git
}

main
