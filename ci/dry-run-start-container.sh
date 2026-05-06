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
##   - Pulls and starts the image, installs systemd-sysv inside it,
##     then exec()s /sbin/init as PID 1.
##   - Polls `systemctl is-system-running` until it reports running
##     or degraded, or fails after 90s (bumped from 60s to give the
##     systemd-sysv apt install ~10s of headroom on top of normal
##     boot).
##
## Image choice:
##   The Debian project does not publish an official systemd-enabled
##   debian:trixie image, so we install systemd-sysv into the
##   minimal base image inside the container before exec'ing init.
##   This is one extra apt round-trip (~5-10s) per workflow run.
##   Switching to a third-party systemd-debian image was rejected
##   because we want to keep the trust footprint at "Debian Project
##   official base image" and not import a community image.

set -o errexit
set -o nounset
set -o pipefail

if [ "$#" -ne 2 ]; then
   printf '%s\n' "usage: ${BASH_SOURCE[0]} <container-name> <image>" >&2
   exit 64
fi

container_name="$1"
image="$2"

## Bash heredoc-style entrypoint for the container:
##   1. apt-get update + apt-get install systemd-sysv (so /sbin/init
##      exists; the minimal debian:trixie image does not ship it).
##   2. exec /sbin/init so systemd takes over PID 1.
## Single-quoted to keep the inner script literal at the docker-cli
## boundary; no shell expansion happens on the host side.
entrypoint='set -o errexit; set -o nounset; set -o pipefail; \
export DEBIAN_FRONTEND=noninteractive; \
apt-get update -qq; \
apt-get install --yes --no-install-recommends -- systemd-sysv ca-certificates; \
exec /sbin/init'

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
   bash -c "${entrypoint}"

## Wait for systemd to reach a usable state. is-system-running returns
## "running" or "degraded" once the basic targets are up; both are
## acceptable for our purposes (we don't need every target up, just
## the ability to start units like approx). 90s budget covers a
## ~10s apt install + normal boot; if the runner is unusually slow,
## bump this rather than failing the whole dry-run.
for attempt in $(seq 1 90); do
   state="$(docker exec "${container_name}" systemctl is-system-running 2>/dev/null || true)"
   case "${state}" in
      running|degraded)
         printf '%s\n' "systemd state: ${state} (after ${attempt}s)"
         exit 0
         ;;
   esac
   sleep 1
done

printf '%s\n' "ERROR: systemd did not become ready within 90s" >&2
docker exec "${container_name}" systemctl --failed || true
exit 1
