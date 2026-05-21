#!/bin/bash

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## Debugging.
pwd

## Source help-steps/pre for xtrace_off / xtrace_restore and error-handler
## plumbing. Opt into fail-fast mode so pre keeps errexit on:
##   - dist_build_auto_retry=0          no automatic retry on failure
##   - dist_build_interactive=false     no interactive "continue/retry" menu
## Under those flags, pre's ERR trap always ends with an explicit 'exit 1',
## so the caller's 'set -o errexit' above is preserved.
export dist_build_auto_retry=0
export dist_build_interactive=false

source ./help-steps/pre
source ./automated_builder/scripts/functions.bash

## Silence xtrace around the secret-bearing 'export' so the password is not
## echoed to CI logs. Safe to restore afterwards: the only subsequent
## reference - write_password - silences xtrace inside itself.
xtrace_off
export ANSIBLE_VAULT_PASSWORD="$1"
xtrace_restore

export ANSIBLE_HOST_KEY_CHECKING=False

main() {
  decrypt_vault
  run_builder
  encrypt_vault
}

run_builder() {
  ansible-galaxy collection install community.digitalocean community.general
  ## '-i localhost,' is Ansible inline-inventory syntax (trailing comma
  ## means "host list", not a filename). Pairs with hosts:localhost +
  ## connection:local in delete_inventory.yml. Without -i, ansible-playbook
  ## emits "No inventory was parsed" / "provided hosts list is empty"
  ## warnings on every invocation.
  ansible-playbook -i localhost, automated_builder/roles/common/tasks/delete_inventory.yml
  ansible-playbook -i automated_builder/inventory automated_builder/main.yml
}

main
