#!/bin/bash

#set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## xtrace_off / xtrace_restore come from help-steps/pre, which the three
## CI entrypoint scripts source before sourcing this file.

export ANSIBLE_CONFIG="${PWD}/automated_builder/ansible.cfg"

## Duplicated in .github/workflows/local-test-build.yml
## (actions/upload-artifact 'path:'); keep the two in sync.
automated_builder_logs_dir="./automated_builder/logs"

decrypt_vault() {
  check_vault_value
  if [ "${ANSIBLE_VAULT_VALUE:-}" == "ANSIBLE_VAULT" ]; then
    write_password
    ansible-vault decrypt --vault-password-file ansible_vault_password automated_builder/roles/common/vars/secrets.yml
    rm -- ansible_vault_password
  fi
}

encrypt_vault() {
  check_vault_value
  if [ "${ANSIBLE_VAULT_VALUE:-}" != "ANSIBLE_VAULT" ]; then
    write_password
    ansible-vault encrypt --vault-password-file ansible_vault_password automated_builder/roles/common/vars/secrets.yml
    rm -- ansible_vault_password
  fi
}

write_password() {
  ## 'local -' saves the current shell options (including xtrace) and
  ## restores them when this function returns, so 'set +x' below silences
  ## the secret only for the duration of this function - no trap needed.
  local -
  set +x
  ## Subshell so 'umask 077' only applies to the 'tee' inside and does
  ## not leak into the caller - analogous to what 'local -' does for
  ## shell options.
  (
    umask 077
    printf '%s\n' "$ANSIBLE_VAULT_PASSWORD" | tee -- ansible_vault_password >/dev/null
  )
}

check_vault_value() {
  ANSIBLE_VAULT_VALUE=$(head -n 1 automated_builder/roles/common/vars/secrets.yml | cut -d ';' -f1 | sed 's/\$//g')
}
