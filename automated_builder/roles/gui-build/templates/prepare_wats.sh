#!/bin/bash

main() {
  prepare_environment
  install_source
}

prepare_environment() {
  dsudo apt-get update -q
  dsudo apt-get install git python3-behave python3-pip python3-pyatspi python3-dogtail -yq --no-install-recommends
  dsudo -H -u user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings set org.gnome.desktop.interface toolkit-accessibility true
  dsudo chmod 744 /etc/python3*
}

install_source() {
  cd /home/user/
  git clone https://github.com/Mycobee/whonix_automated_test_suite.git
}

main
