#!/usr/bin/env bash
# Restores a service's volume, backed up by components/volsync, replacing its contents.
#
# Usage: restore.sh --service NAME [--volume NAME] [--source nas|cloud] [--restore-point TIME]
#        restore.sh --service NAME [--volume NAME] [--source nas|cloud] --list
#   --service        the app, as its Flux Kustomization's APP
#   --volume         the volume to restore; defaults to the service's only one
#   --source         where to restore from; defaults to nas, or every source with --list
#   --restore-point  RFC 3339 time, e.g. 2026-11-22T16:00:00Z; defaults to the latest backup
#   --list           lists the backups to choose a restore point from, changing nothing
#
# Asks before stopping the service, restores the newest backup at or before the
# restore point, then hands the service back to Flux. On a failure it stops with
# the service still down.
set -euo pipefail

# shellcheck source=scripts/libs/volsync.sh
source "$(dirname "$0")/libs/volsync.sh"

usage() {
  sed -n '2,/^set /{/^#/s/^# \{0,1\}//p;}' "$0" >&2
  exit 2
}

service='' volume='' source='' restore_point='' list=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --help) usage ;;
    --list) list=true; shift; continue ;;
  esac
  [[ $# -ge 2 ]] || { echo "$1 needs a value" >&2; usage; }
  case $1 in
    --service) service=$2 ;;
    --volume) volume=$2 ;;
    --source) source=$2 ;;
    --restore-point) restore_point=$2 ;;
    *) echo "unknown option $1" >&2; usage ;;
  esac
  shift 2
done
[[ -n $service ]] || { echo "--service is required" >&2; usage; }
if [[ -n $restore_point && ! $restore_point =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}(Z|[+-][0-9]{2}:[0-9]{2})$ ]]; then
  echo "--restore-point must be RFC 3339, such as 2026-11-22T16:00:00Z" >&2
  exit 2
fi

find_volume "$service" "$volume"
namespace=$service claim=$volume

if $list; then
  if [[ -n $source ]]; then
    sources=replicationsource/$claim-$source
    kubectl -n "$namespace" get "$sources" >/dev/null \
      || { echo "no ReplicationSource $namespace/$claim-$source; is $source set up for $service?" >&2; exit 1; }
  else
    sources=$(replication_sources "$namespace" "$claim")
    [[ -n $sources ]] || { echo "$claim has no ReplicationSources" >&2; exit 1; }
  fi
  for rs in $sources; do
    rs=${rs#replicationsource/}
    echo "${rs#"$claim"-}"
    # rclone can log to stderr too, which shares the pod log; restic prints the JSON as one line.
    run_restic "$namespace" "$rs" snapshots --json --host volsync | grep '^\[' | tail -n 1 | jq -r '
      def size: if . == null then "-" elif . >= 1073741824 then "\(. / 1073741824 * 10 | round / 10) GiB"
        else "\(. / 1048576 | round) MiB" end;
      if length == 0 then "  no backups" else
        sort_by(.time) | reverse[]
        # To the second in UTC, as --restore-point takes it; the restore also ignores fractions.
        | "  \(.time | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | . as $time | try (fromdate | todate) catch $time)  \(.short_id)  \(.summary.total_bytes_processed | size)"
      end'
  done
  exit 0
fi

source=${source:-nas}
rs_name=$claim-$source
rs=$(kubectl -n "$namespace" get replicationsource "$rs_name" -o json) \
  || { echo "no ReplicationSource $namespace/$rs_name; is $source set up for $service?" >&2; exit 1; }
# Every target's ReplicationSource for this volume, so none backs up mid-restore.
sources=$(replication_sources "$namespace" "$claim")

cat <<EOF
Service:        $service (Flux Kustomization $kustomization)
Volume:         $claim
Source:         $source, last backed up $(jq -r '.status.lastSyncTime // "never"' <<<"$rs")
Restore point:  ${restore_point:-latest backup}

This stops $service and replaces everything on $claim with that backup.
EOF
read -r -p "Continue? [y/N] " answer </dev/tty
[[ $answer == [yY] ]] || { echo "Nothing changed"; exit 1; }

echo "Suspending $kustomization and pausing its backups"
flux suspend kustomization "$kustomization"
trap 'echo "stopped with $kustomization suspended; when done: flux resume kustomization $kustomization" >&2' EXIT
# shellcheck disable=SC2086 # one word per ReplicationSource
kubectl -n "$namespace" patch $sources --type merge -p '{"spec":{"paused":true}}'

# A restore needs the volume to itself.
stop_claim_users "$namespace" "$claim"

# Reuses the ReplicationSource's settings, so a restore matches how the backup was taken.
trigger=restore-$(date -u +%Y%m%dT%H%M%SZ)
jq --arg claim "$claim" --arg trigger "$trigger" --arg restore_point "$restore_point" '{
  apiVersion: "volsync.backube/v1alpha1",
  kind: "ReplicationDestination",
  metadata: {name: ($claim + "-restore"), namespace: .metadata.namespace},
  spec: {
    trigger: {manual: $trigger},
    restic: ({
      repository: .spec.restic.repository,
      copyMethod: "Direct",
      destinationPVC: $claim,
      enableFileDeletion: true,
      cacheStorageClassName: .spec.restic.cacheStorageClassName,
      cacheCapacity: .spec.restic.cacheCapacity,
      cleanupCachePVC: true,
      moverSecurityContext: .spec.restic.moverSecurityContext,
      moverVolumes: .spec.restic.moverVolumes
    } + if $restore_point == "" then {} else {restoreAsOf: $restore_point} end)
  }
} | del(.. | nulls)' <<<"$rs" | kubectl apply -f -

echo "Restoring $namespace/$claim from $source, ${restore_point:-latest backup}"
# BAK-009 allows 4 hours for a restore.
kubectl -n "$namespace" wait "replicationdestination/$claim-restore" \
  --for=jsonpath="{.status.lastManualSync}=$trigger" --timeout=4h
result=$(kubectl -n "$namespace" get replicationdestination "$claim-restore" -o jsonpath='{.status.latestMoverStatus.result}')
if [[ $result != Successful ]]; then
  kubectl -n "$namespace" get replicationdestination "$claim-restore" -o jsonpath='{.status.latestMoverStatus.logs}' >&2
  echo "restore $result" >&2
  exit 1
fi
kubectl -n "$namespace" get replicationdestination "$claim-restore" -o jsonpath='{.status.latestMoverStatus.logs}{"\n"}'
kubectl -n "$namespace" delete replicationdestination "$claim-restore"

# A paused ReplicationSource keeps the clone it took when created, so Flux recreates
# them to clone the restored data rather than what was there before.
# shellcheck disable=SC2086 # one word per ReplicationSource
kubectl -n "$namespace" delete $sources --wait

# Flux puts back the replica counts and spec.paused from Git.
echo "Resuming $kustomization"
trap - EXIT
flux resume kustomization "$kustomization"
