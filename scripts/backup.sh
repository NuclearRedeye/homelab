#!/usr/bin/env bash
# Backs up a service's volume now, to targets set up by components/volsync.
#
# Usage: backup.sh --service NAME [--volume NAME] [--target nas|cloud] [--stop] [--archive NAME]
#   --service  the app, as its Flux Kustomization's APP
#   --volume   the volume to back up; defaults to the service's only one
#   --target   where to back up to; defaults to every target
#   --stop     stops the service during the backup, then starts it again
#   --archive  keeps the backup until deleted by hand, under NAME (lowercase letters, digits and hyphens)
#
# Without --stop the backup is crash-consistent, like the nightly ones. Each
# target's ReplicationSource goes back on its schedule afterwards, even on a failure.
#
# An archived backup moves to restic host "archive", which VolSync's retention
# never prunes, as its forget only looks at host "volsync".
set -euo pipefail

# shellcheck source=scripts/libs/volsync.sh
source "$(dirname "$0")/libs/volsync.sh"

usage() {
  sed -n '2,/^set /{/^#/s/^# \{0,1\}//p;}' "$0" >&2
  exit 2
}

service='' volume='' target='' stop=false archive=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --help) usage ;;
    --stop) stop=true; shift; continue ;;
  esac
  [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; usage; }
  case $1 in
    --service) service=$2 ;;
    --volume) volume=$2 ;;
    --target) target=$2 ;;
    --archive) archive=$2 ;;
    *) echo "unknown option $1" >&2; usage ;;
  esac
  shift 2
done
[[ -n $service ]] || { echo "--service is required" >&2; usage; }
if [[ -n $archive && ! $archive =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "--archive must be lowercase letters, digits and hyphens, such as before-update" >&2
  exit 2
fi

find_volume "$service" "$volume"
namespace=$service claim=$volume
if [[ -n $target ]]; then
  sources=replicationsource/$claim-$target
  kubectl -n "$namespace" get "$sources" >/dev/null \
    || { echo "no ReplicationSource $namespace/$claim-$target; is $target set up for $service?" >&2; exit 1; }
else
  sources=$(replication_sources "$namespace" "$claim")
  [[ -n $sources ]] || { echo "$claim has no ReplicationSources" >&2; exit 1; }
fi

for rs in $sources; do
  status=$(kubectl -n "$namespace" get "$rs" -o json)
  # A paused ReplicationSource backs up the clone it took before pausing, not the volume now.
  if [[ $(jq -r '.spec.paused // false' <<<"$status") == true ]]; then
    echo "$rs is paused (VOLSYNC_PAUSED, or the service is suspended); unpause it first" >&2
    exit 1
  fi
  if [[ $(jq -r '.status.conditions[]? | select(.type == "Synchronizing") | .reason' <<<"$status") == SyncInProgress ]]; then
    echo "$rs is already backing up; run this again when it finishes" >&2
    exit 1
  fi
done

# Checks every target first, so a taken name doesn't leave some archived and some not.
if [[ -n $archive ]]; then
  for rs in $sources; do
    # rclone can log to stderr too, which shares the pod log; restic prints the JSON as one line.
    count=$(run_restic "$namespace" "${rs#replicationsource/}" snapshots --json --host archive --tag "$archive" \
      | grep '^\[' | tail -n 1 | jq length)
    if [[ $count != 0 ]]; then
      echo "$claim already has an archive named $archive at ${rs#replicationsource/"$claim"-}; choose another name" >&2
      exit 1
    fi
  done
fi
archived=()

# Flux reverts fields set by kubectl's own field managers, so the trigger needs another.
trigger_manager=backup-sh

# Flux doesn't own trigger.manual, so it would stay and replace the schedule.
finish() {
  for rs in $sources; do
    kubectl -n "$namespace" patch "$rs" --field-manager="$trigger_manager" --type merge -p '{"spec":{"trigger":{"manual":null}}}' >/dev/null \
      || echo "couldn't clear $rs's manual trigger; remove spec.trigger.manual by hand" >&2
  done
  if [[ -n $archive && ${#archived[@]} -lt $(wc -w <<<"$sources") ]]; then
    echo "archived as $archive at: ${archived[*]:-none}; rerun with --target for the rest" >&2
  fi
  if $stop; then
    # Flux puts back the replica counts from Git.
    echo "Resuming $kustomization"
    flux resume kustomization "$kustomization"
  fi
}

if $stop; then
  cat <<EOF
Service:  $service (Flux Kustomization $kustomization)
Volume:   $claim
Targets:  $(tr '\n' ' ' <<<"${sources//replicationsource\//}")

This stops $service until the backup finishes.
EOF
  read -r -p "Continue? [y/N] " answer </dev/tty
  [[ $answer == [yY] ]] || { echo "Nothing changed"; exit 1; }
fi

trap finish EXIT
if $stop; then
  echo "Suspending $kustomization"
  flux suspend kustomization "$kustomization"
  stop_claim_users "$namespace" "$claim"
fi

# One target at a time, as the nightly runs are staggered.
for rs in $sources; do
  trigger=backup-$(date -u +%Y%m%dT%H%M%SZ)
  echo "Backing up $namespace/$claim with $rs"
  kubectl -n "$namespace" patch "$rs" --field-manager="$trigger_manager" --type merge \
    -p "{\"spec\":{\"trigger\":{\"manual\":\"$trigger\"}}}" >/dev/null
  # TODO: VolSync retries a failed mover, so a failure waits out the timeout; watch latestMoverStatus too.
  kubectl -n "$namespace" wait "$rs" --for=jsonpath="{.status.lastManualSync}=$trigger" --timeout=4h >/dev/null
  status=$(kubectl -n "$namespace" get "$rs" -o json)
  if [[ $(jq -r '.status.latestMoverStatus.result' <<<"$status") != Successful ]]; then
    jq -r '.status.latestMoverStatus.logs' <<<"$status" >&2
    echo "$rs backup $(jq -r '.status.latestMoverStatus.result' <<<"$status")" >&2
    exit 1
  fi
  jq -r '.status.latestMoverStatus.logs' <<<"$status"
  # Any restore point at or after this time picks up the backup.
  echo "Backed up at $(jq -r '.status.lastSyncTime' <<<"$status")"
  if [[ -n $archive ]]; then
    # Names the backup just taken, then moves it out of retention; a named one left on host volsync just ages out.
    run_restic "$namespace" "${rs#replicationsource/}" tag --add "$archive" --host volsync latest >/dev/null
    run_restic "$namespace" "${rs#replicationsource/}" rewrite --new-host archive --forget --host volsync --tag "$archive" latest >/dev/null
    archived+=("${rs#replicationsource/"$claim"-}")
    echo "Archived as $archive"
  fi
done
