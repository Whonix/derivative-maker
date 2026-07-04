#!/bin/bash

## Copyright (C) 2025 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## TODO: document

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

container=docker
export container

if [ $# -eq 0 ]; then
  printf '%s\n' 'ERROR: No command specified. You probably want to run "journalctl -f", or maybe "bash"?' >&2
  exit 1
fi

## A TTY is only required for interactive use (e.g. "bash", "journalctl -f").
## Headless CI runs deliberately omit "docker run --tty" and set CI=true.
if [ ! -t 0 ] && [ "${CI:-}" != "true" ]; then
  printf '%s\n' 'ERROR: TTY needs to be enabled ("docker run -t ...").' >&2
  exit 1
fi

env | tee -- /etc/docker-entrypoint-env >/dev/null

## Debugging.
cat -- /etc/docker-entrypoint-env

quoted_args="$(printf " %q" "${@}")"
printf '%s\n' "${quoted_args}" | tee -- /etc/docker-entrypoint-cmd >/dev/null
chmod +x -- /etc/docker-entrypoint-cmd

systemctl mask systemd-firstboot.service systemd-udevd.service systemd-modules-load.service
systemctl unmask systemd-logind
systemctl enable docker-entrypoint.service

systemd=
if [ -x /lib/systemd/systemd ]; then
  systemd=/lib/systemd/systemd
elif [ -x /usr/lib/systemd/systemd ]; then
  systemd=/usr/lib/systemd/systemd
elif [ -x /sbin/init ]; then
  systemd=/sbin/init
else
  printf '%s\n' 'ERROR: systemd is not installed' >&2
  exit 1
fi

declare -a systemd_args=(
  --show-status=false
  --unit=docker-entrypoint.target
)

printf '%s\n' "$0: starting $systemd ${systemd_args[*]}"

exec "$systemd" "${systemd_args[@]}"
