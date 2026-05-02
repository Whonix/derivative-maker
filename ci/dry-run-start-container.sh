#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Bring up a privileged Debian container with systemd booted as PID 1
## for .github/workflows/dry-run.yml. The workflow's other steps
## docker-exec into the running container.
##
## Why this lives in a script instead of inline in the workflow YAML:
## per agents/bash-style-guide.md, substantial bash logic (>~5 lines)
## belongs in a standalone script that can be shellcheck'd, run from
## a developer machine for reproduction, and reviewed independently
## of the workflow shape.
##
## Inputs:
##   $1 - container name to assign (e.g. "dryrun")
##   $2 - debian image reference (digest-pinned recommended)
##
## Side effects:
##   - Pulls and starts the image with /sbin/init as entrypoint.
##   - Polls `systemctl is-system-running` until it reports running
##     or degraded, or fails after 60s.

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -ne 2 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <container-name> <image>" >&2
   exit 64
fi

container_name="$1"
image="$2"

docker run \
   --detach \
   --rm \
   --privileged \
   --name "${container_name}" \
   --tmpfs /run \
   --tmpfs /run/lock \
   --volume /sys/fs/cgroup:/sys/fs/cgroup:rw \
   --volume "${PWD}":/work \
   --workdir /work \
   -- \
   "${image}" \
   /sbin/init

## Wait for systemd to reach a usable state. is-system-running returns
## "running" or "degraded" once the basic targets are up; both are
## acceptable for our purposes (we don't need every target up, just
## the ability to start units like approx).
for attempt in $(seq 1 60); do
   state="$(docker exec "${container_name}" systemctl is-system-running 2>/dev/null || true)"
   case "${state}" in
      running|degraded)
         printf '%s\n' "systemd state: ${state} (after ${attempt}s)"
         exit 0
         ;;
   esac
   sleep 1
done

printf '%s\n' "ERROR: systemd did not become ready within 60s" >&2
docker exec "${container_name}" systemctl --failed || true
exit 1
