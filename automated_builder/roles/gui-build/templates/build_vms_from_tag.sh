#!/bin/bash

export dist_build_non_interactive=true

main() {
  build_debug_vms >> /home/ansible/debug_build.log 2>&1
  build_gateway_vm >> /home/ansible/gateway_build.log 2>&1
  build_workstation_vm >> /home/ansible/workstation_build.log 2>&1
}

build_gateway_vm() {
  /home/ansible/derivative-maker/derivative-maker \
    --flavor whonix-gateway-xfce \
    --target virtualbox \
    --build
}

build_workstation_vm() {
  /home/ansible/derivative-maker/derivative-maker \
    --flavor whonix-workstation-xfce \
    --target virtualbox \
    --build
}

build_debug_vms() {
  if [[ "$DEBUG_BUILD" == "true" ]]; then
    wget https://download.whonix.org/ova/{{ DEBUG_BUILD_VERSION }}/Whonix-CLI-{{ DEBUG_BUILD_VERSION }}.ova
    VBoxManage import Whonix-CLI-{{ DEBUG_BUILD_VERSION }}.ova --vsys 1 --eula accept  --vsys 0 --eula accept
  fi
  exit 0
}

main
