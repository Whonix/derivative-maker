#!/bin/bash

# Written by Jason Mehring (nrgaway@gmail.com)
# Modified by Patrick Schleizer (adrelanos@whonix.org)

#set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

true "$0 INFO: start"

if [ "$EUID" != "0" ]; then
   printf '%s\n' "$0: ERROR: This MUST be run as root (sudo)!" >&2
   exit 1
fi

file_system_object="${1:-}"

if [ "${file_system_object:-}" = "" ]; then
   printf '%s\n' "$0: ERROR: no parameter given!" >&2
   exit 1
fi

if [ "${file_system_object:-}" = "/" ]; then
   printf '%s\n' "$0: ERROR: file_system_object is set to / which is probably wrong (would kill all processes including this script)!" >&2
   exit 1
fi

if ! test -e "$file_system_object" ; then
   true "$0: INFO: file_system_object does not exist. Skip checking if processes are running there, ok."
   true "$0: INFO: end"
   exit 0
fi

real_path=$(realpath -- "$file_system_object") || true

## Hard guard: with an empty '$real_path' the prefix patterns below
## ('"${real_path}"/*') would degenerate to '/*' and match EVERY process on
## the system; with '/' they would too (and '/' is already rejected above
## for '$file_system_object').
if [ "${real_path:-}" = "" ] || [ "${real_path:-}" = "/" ]; then
   printf '%s\n' "$0: ERROR: could not canonicalize file_system_object '$file_system_object' (realpath returned '${real_path:-}')." >&2
   exit 1
fi

if [ "${file_system_object:-}" = "$real_path" ]; then
   true "INFO: file_system_object = real_path, ok."
else
   if test -L "$file_system_object" ; then
      true "INFO: symlink"
   else
      printf '%s\n' "INFO: real_path: '$real_path'"
      printf '%s\n' "INFO: file_system_object: '$file_system_object'"
      printf '%s\n' "WARNING: file_system_object is different from real_path!" >&2
   fi
fi

skip_name_list="pts dev proc sys hostname resolv.conf hosts hostname"

base_name="${file_system_object##*/}"

for skip_name_item in $skip_name_list ; do
   if [ "${base_name:-}" = "$skip_name_item" ]; then
      ## Most likely just mounted host /dev in chroot can be ignored.
      ## Would otherwise show a long, confusing lsof.
      true "$0: INFO: base_name: $skip_name_item Skip checking if processes are running there, ok."
      true "$0: INFO: end"
      exit 0
   fi
done

true "INFO: Checking if there are any processes still running in file_system_object: '$file_system_object'"

## Print the PIDs of every process still using '$real_path': chrooted into
## it, cwd inside it, executing a binary from it, holding any open file
## descriptor under it, or mmap-ing a file under it.
##
## Detection is /proc-based and dependency-free. The previous implementation
## ran a single 'lsof -- <dir>', which matches a directory ARGUMENT by that
## one inode only: a process whose open files merely live UNDER the
## directory (a lingering chroot daemon's log file, socket, cwd in a
## subdirectory, ...) was missed, and a missing 'lsof' binary degraded into
## a silent "no pids" verdict ('2>/dev/null' plus '|| true' swallowed the
## command-not-found). Scanning '/proc/<pid>/{root,cwd,exe,fd/*}' via
## 'readlink' catches everything 'lsof' caught for this use case plus the
## under-the-tree cases; the '/proc/<pid>/maps' grep covers mmap-only users.
## The kernel keeps these link targets current across a rename of the tree
## (pbuilder's move of the cowbuilder work directory onto 'base.cow'), so a
## prefix comparison against the canonical path stays correct even after
## that move.
## Exact-boundary check of one '/proc/<pid>/maps' file against
## '$real_path'. A plain substring match would false-positive on a sibling
## path sharing the string prefix (e.g. '.../derivative-binary' vs
## '.../derivative-binary_vbox-workdir') and get an innocent process
## killed. The pathname field starts at field 6, may itself contain spaces,
## and carries a trailing ' (deleted)' suffix for deleted files
## (proc_pid_maps(5)); parse accordingly, then match with path-boundary
## semantics.
maps_file_matches() {
   local maps_file maps_address maps_perms maps_offset maps_dev maps_inode maps_pathname

   maps_file="$1"
   while read -r maps_address maps_perms maps_offset maps_dev maps_inode maps_pathname; do
      [ -n "${maps_pathname}" ] || continue
      maps_pathname="${maps_pathname% (deleted)}"
      case "${maps_pathname}" in
         "${real_path}" | "${real_path}"/*)
            return 0
            ;;
      esac
   done < "${maps_file}"
   return 1
}

pids_using_path() {
   local proc_entry proc_pid link_target_lines link_target

   for proc_entry in /proc/[0-9]*; do
      proc_pid="${proc_entry##*/}"
      ## Never list this script itself or its invoking parent ('sudo').
      ## '$$' and '$PPID' stay those of the script even inside the
      ## command-substitution subshell that calls this function.
      if [ "${proc_pid}" = "$$" ] || [ "${proc_pid}" = "${PPID}" ]; then
         continue
      fi
      ## One 'readlink' invocation per process: prints one resolved target
      ## per line, skips unreadable entries (exits non-zero then, hence
      ## '|| true'). Kernel threads have no readable 'exe'/'fd'; vanished
      ## processes disappear mid-scan; both end up as empty output.
      link_target_lines="$(readlink -- "${proc_entry}/root" "${proc_entry}/cwd" "${proc_entry}/exe" "${proc_entry}"/fd/* 2>/dev/null)" || true
      while IFS="" read -r link_target; do
         case "${link_target}" in
            "${real_path}" | "${real_path}"/*)
               printf '%s\n' "${proc_pid}"
               continue 2
               ;;
         esac
      done <<< "${link_target_lines}"
      ## mmap-only usage (shared library mapped from inside the tree while
      ## root/cwd/exe/fds all point elsewhere). 'grep -F' (literal match, no
      ## regex metacharacter surprises) is only a cheap substring PRE-filter
      ## so the common no-hit case stays one grep per process; a hit is then
      ## verified with exact path-boundary matching ('maps_file_matches')
      ## before the process is listed.
      if grep --quiet --fixed-strings -- "${real_path}" "${proc_entry}/maps" 2>/dev/null; then
         if maps_file_matches "${proc_entry}/maps"; then
            printf '%s\n' "${proc_pid}"
         fi
      fi
   done
}

pids="$(pids_using_path)"

if [ "${pids:-}" = "" ]; then
   true "INFO: Okay, no pids still running in '$file_system_object', no need to kill any."
else
   printf '%s\n' "INFO: Okay, the following pids are still running inside '$file_system_object', which will now be killed."

   ## Debugging.
   ## Overwrite with '|| true' to avoid race condition if these processes already
   ## terminated themselves.
   ## Word-splitting of '$pids' is intentional (one PID per line).
   # shellcheck disable=SC2086
   ps -p $pids || printf '%s\n' "WARNING: Command 'ps -p $pids' exited non-zero." >&2

   ## SIGTERM first: a daemon such as 'VBoxSVC' shuts down cleanly on it
   ## (flushes state, removes its sockets), whereas SIGKILL guarantees stale
   ## runtime litter. Escalate only if something is still alive after the
   ## grace period.
   # shellcheck disable=SC2086
   kill -s TERM -- $pids || printf '%s\n' "WARNING: Command 'kill -s TERM -- $pids' exited non-zero." >&2

   grace_seconds_left=5
   pids="$(pids_using_path)"
   while [ ! "${pids}" = "" ] && [ "${grace_seconds_left}" -gt 0 ]; do
      sleep 1
      grace_seconds_left=$((grace_seconds_left - 1))
      pids="$(pids_using_path)"
   done

   if [ ! "${pids}" = "" ]; then
      printf '%s\n' "WARNING: The following pids survived SIGTERM and the grace period, sending SIGKILL: $pids" >&2
      # shellcheck disable=SC2086
      kill -s KILL -- $pids || printf '%s\n' "WARNING: Command 'kill -s KILL -- $pids' exited non-zero." >&2
      ## Killing processes is not instant; give the kernel a moment before
      ## callers proceed to unmount / delete the tree.
      sleep 3
   fi
fi

## After killing the processes that held the tree busy, UNMOUNT every mount UNDER
## it (deepest first). Without this a still-mounted /sys, /dev/pts or /proc leaves
## the tree un-copyable ('cp -al' -> "Invalid cross-device link") and un-removable
## -- which breaks cowbuilder base setup (the base.cow -> cow.1 COW copy that
## 'cowbuilder --execute' does) and chroot teardown. '--lazy --force' so a
## transient-busy mount still detaches. Captured first so pipefail cannot abort on
## an empty match.
umount_kill_mounts="$(findmnt --raw --noheadings --output TARGET 2>/dev/null | awk -v base="${file_system_object%/}" '$0 == base || index($0, base"/") == 1' | LC_ALL=C sort --reverse || true)"
if [ -n "${umount_kill_mounts}" ]; then
   while IFS="" read -r umount_kill_mp; do
      [ -n "${umount_kill_mp}" ] || continue
      umount --lazy --force -- "${umount_kill_mp}" 2>/dev/null \
         || printf '%s\n' "$0: WARNING: umount '${umount_kill_mp}' failed." >&2
   done <<< "${umount_kill_mounts}"
fi

true "$0 INFO: end"
