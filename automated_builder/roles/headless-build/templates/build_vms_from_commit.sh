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
    --remote-derivative-packages true \
    --allow-untagged true \
    --build
}

build_workstation_vm() {
  /home/ansible/derivative-maker/derivative-maker \
    --flavor whonix-workstation-xfce \
    --target virtualbox \
    --remote-derivative-packages true \
    --allow-untagged true \
    --build
}

build_debug_vms() {
  echo DEBUG_LOG: $DEBUG_LOG
  if [[ "$DEBUG_BUILD" == "true" ]]; then
    wget https://download.whonix.org/ova/{{ DEBUG_BUILD_VERSION }}/Whonix-XFCE-{{ DEBUG_BUILD_VERSION }}.ova
    VBoxManage import Whonix-XFCE-{{ DEBUG_BUILD_VERSION }}.ova --vsys 1 --eula accept  --vsys 0 --eula accept
    exit 0
  fi
}

main
