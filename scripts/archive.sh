#!/usr/bin/env bash
# Deletes a service's archived backup, made by backup.sh --archive, from targets set up by components/volsync.
#
# Usage: archive.sh --service NAME [--volume NAME] [--target nas|cloud] --delete NAME
#   --service  the app, as its Flux Kustomization's APP
#   --volume   the volume the archive is of; defaults to the service's only one
#   --target   where to delete it from; defaults to every target
#   --delete   the archive to delete, as restore.sh --list shows it
#
# Asks first, and only ever deletes snapshots on restic host "archive". Their
# data is freed at the next prune.
set -euo pipefail

# shellcheck source=scripts/libs/volsync.sh
source "$(dirname "$0")/libs/volsync.sh"

usage() {
  sed -n '2,/^set /{/^#/s/^# \{0,1\}//p;}' "$0" >&2
  exit 2
}

service='' volume='' target='' archive=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --help) usage ;;
  esac
  [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; usage; }
  case $1 in
    --service) service=$2 ;;
    --volume) volume=$2 ;;
    --target) target=$2 ;;
    --delete) archive=$2 ;;
    *) echo "unknown option $1" >&2; usage ;;
  esac
  shift 2
done
[[ -n $service ]] || { echo "--service is required" >&2; usage; }
[[ -n $archive ]] || { echo "--delete is required" >&2; usage; }

find_volume "$service" "$volume"
namespace=$service claim=$volume
sources=$(replication_sources "$namespace" "$claim" "$target")

# Finds the archive at every target first, so the prompt shows everything that will go.
declare -A ids
found='' lines=''
for rs in $sources; do
  rs=${rs#replicationsource/}
  # rclone can log to stderr too, which shares the pod log; restic prints the JSON as one line.
  snapshots=$(run_restic "$namespace" "$rs" snapshots --json --host archive --tag "$archive" | grep '^\[' | tail -n 1)
  ids[$rs]=$(jq -r '[.[].id] | join(" ")' <<<"$snapshots")
  lines=$(jq -r --arg target "${rs#"$claim"-}" '.[] | [$target, .short_id, .time] | @tsv' <<<"$snapshots")
  [[ -z $lines ]] || found+=$lines$'\n'
done
[[ -n $found ]] || { echo "$claim has no archive named $archive; see restore.sh --list" >&2; exit 1; }

cat <<EOF
Service:  $service
Volume:   $claim
Archive:  $archive

This deletes these snapshots:
$(column -t -s $'\t' <<<"${found%$'\n'}" | sed 's/^/  /')
EOF
read -r -p "Continue? [y/N] " answer </dev/tty
[[ $answer == [yY] ]] || { echo "Nothing changed"; exit 1; }

for rs in "${!ids[@]}"; do
  [[ -n ${ids[$rs]} ]] || continue
  # By ID, from the host archive lookup above, so nothing else can match.
  # shellcheck disable=SC2086 # one word per snapshot ID
  run_restic "$namespace" "$rs" forget ${ids[$rs]} >/dev/null
  echo "Deleted $archive at ${rs#"$claim"-}"
done
