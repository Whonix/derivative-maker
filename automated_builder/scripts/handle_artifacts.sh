#!/bin/bash

#set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## Source help-steps/pre for xtrace_off / xtrace_restore and error-handler
## plumbing. Opt into fail-fast mode so pre keeps errexit on.
export dist_build_auto_retry=0
export dist_build_non_interactive=true
source ./help-steps/pre
source ./automated_builder/scripts/functions.bash

## Silence xtrace around the secret-bearing 'export' so the password is not
## echoed to CI logs. Safe to restore afterwards: the only subsequent
## reference - write_password - silences xtrace inside itself.
xtrace_off
export ANSIBLE_VAULT_PASSWORD="$1"
xtrace_restore

export ANSIBLE_HOST_KEY_CHECKING=False

## Ansible's fetch module does not auto-mkdir the dest tree, and
## upload-artifacts fails the step if the dir is missing on the
## "remote VPS unreachable" failure path.
mkdir -p -- "${automated_builder_logs_dir}"

main() {
  decrypt_vault
  gather_logs
  encrypt_vault
}

gather_logs() {
  ansible-playbook -i automated_builder/inventory \
    -e "logs_dir=${automated_builder_logs_dir}" \
    automated_builder/gather_build_logs.yml
}

main
