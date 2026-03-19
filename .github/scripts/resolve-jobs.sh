#!/bin/bash

## Determines which CI jobs to run based on workflow dispatch inputs.
## Outputs a JSON array of job names to GITHUB_OUTPUT.
##
## Usage: resolve-jobs.sh <build_group> <distro> <flavor> <target> <arch>
##   All arguments default to "all" if empty.

set -euo pipefail

build_group="${1:-all}"
distro="${2:-all}"
flavor="${3:-all}"
target="${4:-all}"
arch="${5:-all}"

## Every possible job, one per line: distro|flavor|target|arch
all_jobs=(
  "whonix|lxqt|virtualbox|amd64"
  "whonix|cli|virtualbox|amd64"
  "kicksecure|lxqt|virtualbox|amd64"
  "kicksecure|cli|virtualbox|amd64"
  "whonix|lxqt|raw|amd64"
  "whonix|cli|raw|amd64"
  "kicksecure|lxqt|raw|amd64"
  "kicksecure|cli|raw|amd64"
  "whonix|lxqt|raw|arm64"
  "whonix|cli|raw|arm64"
  "kicksecure|lxqt|raw|arm64"
  "kicksecure|cli|raw|arm64"
  "kicksecure|lxqt|iso|amd64"
  "kicksecure|cli|iso|amd64"
  "kicksecure|lxqt|iso|arm64"
  "kicksecure|cli|iso|arm64"
)

enabled=()

for entry in "${all_jobs[@]}"; do
  IFS='|' read -r j_distro j_flavor j_target j_arch <<< "$entry"
  job_name="${j_distro}-${j_flavor}-${j_target}-${j_arch}"

  case "$build_group" in
    all)
      enabled+=("$job_name")
      ;;
    whonix-all)
      [[ "$j_distro" == "whonix" ]] && enabled+=("$job_name")
      ;;
    kicksecure-all)
      [[ "$j_distro" == "kicksecure" ]] && enabled+=("$job_name")
      ;;
    vbox-all)
      [[ "$j_target" == "virtualbox" ]] && enabled+=("$job_name")
      ;;
    raw-all)
      [[ "$j_target" == "raw" ]] && enabled+=("$job_name")
      ;;
    iso-all)
      [[ "$j_target" == "iso" ]] && enabled+=("$job_name")
      ;;
    custom)
      [[ "$distro" != "all" && "$distro" != "$j_distro" ]] && continue
      [[ "$flavor" != "all" && "$flavor" != "$j_flavor" ]] && continue
      [[ "$target" != "all" && "$target" != "$j_target" ]] && continue
      [[ "$arch"   != "all" && "$arch"   != "$j_arch"   ]] && continue
      enabled+=("$job_name")
      ;;
  esac
done

## Build JSON array
json="["
for i in "${!enabled[@]}"; do
  [[ $i -gt 0 ]] && json+=","
  json+="\"${enabled[$i]}\""
done
json+="]"

echo "Enabled jobs: $json"
echo "jobs=$json" >> "$GITHUB_OUTPUT"
