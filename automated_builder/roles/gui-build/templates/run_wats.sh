#!/bin/bash

main() {
  run_tests
}

run_tests() {
  cd /home/user/whonix_automated_test_suite
  DISPLAY=:0 xhost +
  NO_AT_BRIDGE=1 DISPLAY=:0 behave ./features
}

main
