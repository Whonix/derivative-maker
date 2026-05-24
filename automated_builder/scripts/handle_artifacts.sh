#!/bin/bash

#set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

## Source help-steps/pre for xtrace_off / xtrace_restore and error-handler
## plumbing. Opt into fail-fast mode so pre keeps errexit on.
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

## Ansible's fetch module does not auto-mkdir the dest tree, and
## upload-artifacts fails the step if the dir is missing on the
## "remote VPS unreachable" failure path.
mkdir -p -- "${automated_builder_logs_dir}"

## Guarantee the logs dir holds at least one file so upload-artifact
## always produces a downloadable artifact - even when the VPS log
## fetch below gathers nothing (build/log-fetch failed, or the droplet
## is already gone). The run metadata is itself useful when triaging a
## failed build. GIT_REPO / REF_* / GITHUB_EVENT_NAME come from the
## workflow's job-level env.
{
  printf '%s\n'        "automated_builder run info"
  printf 'date_utc=%s\n' "$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
  printf 'repo=%s\n'     "${GIT_REPO:-unknown}"
  printf 'ref_name=%s\n' "${REF_NAME:-unknown}"
  printf 'ref_type=%s\n' "${REF_TYPE:-unknown}"
  printf 'event=%s\n'    "${GITHUB_EVENT_NAME:-unknown}"
} > "${automated_builder_logs_dir}/run-info.txt"

## ansible.builtin.fetch resolves a relative 'dest' via
## DataLoader.path_dwim, which joins against the playbook's basedir
## (here automated_builder/) not ansible-playbook's cwd. A relative
## "./automated_builder/logs/install_source.log" therefore lands at
## "<repo>/automated_builder/automated_builder/logs/install_source.log"
## (the segment is doubled), while the workflow's mkdir + upload-artifact
## look at "<repo>/automated_builder/logs/" and find nothing. Resolve to
## an absolute path so fetch writes where every other consumer expects.
logs_dir_absolute="$(realpath -- "${automated_builder_logs_dir}")"

main() {
  decrypt_vault
  gather_logs
  encrypt_vault
}

gather_logs() {
  ansible-playbook -i automated_builder/inventory \
    -e "logs_dir=${logs_dir_absolute}" \
    automated_builder/gather_build_logs.yml
}

main
