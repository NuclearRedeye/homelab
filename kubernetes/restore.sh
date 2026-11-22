#!/usr/bin/env bash
# Restores a service's volume, backed up by components/volsync, replacing its contents.
#
# Usage: restore.sh --service NAME [--volume NAME] [--source nas|cloud] [--restore-point TIME]
#   --service        the app, as its Flux Kustomization's APP
#   --volume         the volume to restore; defaults to the service's only one
#   --source         where to restore from; defaults to nas
#   --restore-point  RFC 3339 time, e.g. 2026-11-22T16:00:00Z; defaults to the latest backup
#
# Asks before stopping the service, restores the newest backup at or before the
# restore point, then hands the service back to Flux. On a failure it stops with
# the service still down.
set -euo pipefail

usage() {
  sed -n '2,/^set /{/^#/s/^# \{0,1\}//p;}' "$0" >&2
  exit 2
}

service='' volume='' source=nas restore_point=''
while [[ $# -gt 0 ]]; do
  [[ $1 == --help ]] && usage
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

# Each backed-up volume has its own Flux Kustomization using the component, which requires VOLSYNC_CAPACITY.
volumes=$(kubectl -n flux-system get kustomizations -o json | jq -c --arg service "$service" '
  [.items[] | (.spec.postBuild.substitute // {}) as $values
   | select($values.APP == $service and $values.VOLSYNC_CAPACITY != null)
   | {kustomization: .metadata.name, volume: ($values.VOLSYNC_CLAIM // $values.APP)}]')
if [[ -z $volume ]]; then
  case $(jq length <<<"$volumes") in
    0) echo "$service has no backed-up volumes" >&2; exit 1 ;;
    1) volume=$(jq -r '.[0].volume' <<<"$volumes") ;;
    *) echo "$service has several volumes; choose one with --volume: $(jq -r 'map(.volume) | join(", ")' <<<"$volumes")" >&2; exit 2 ;;
  esac
fi
kustomization=$(jq -er --arg volume "$volume" '.[] | select(.volume == $volume) | .kustomization' <<<"$volumes") \
  || { echo "$service has no backed-up volume $volume" >&2; exit 1; }
namespace=$service claim=$volume
rs_name=$claim-$source
rs=$(kubectl -n "$namespace" get replicationsource "$rs_name" -o json) \
  || { echo "no ReplicationSource $namespace/$rs_name; is $source set up for $service?" >&2; exit 1; }

cat <<EOF
Service:        $service (Flux Kustomization $kustomization)
Volume:         $claim
Source:         $source, last backed up $(jq -r '.status.lastSyncTime // "never"' <<<"$rs")
Restore point:  ${restore_point:-latest backup}

This stops $service and replaces everything on $claim with that backup.
EOF
read -r -p "Continue? [y/N] " answer </dev/tty
[[ $answer == [yY] ]] || { echo "Nothing changed"; exit 1; }

echo "Suspending $kustomization and pausing $rs_name"
flux suspend kustomization "$kustomization"
trap 'echo "stopped with $kustomization suspended; when done: flux resume kustomization $kustomization" >&2' EXIT
kubectl -n "$namespace" patch replicationsource "$rs_name" --type merge -p '{"spec":{"paused":true}}'

# Scale down whatever is running with the volume mounted; a restore needs it to itself.
pods=$(kubectl -n "$namespace" get pods -o json | jq -c --arg claim "$claim" '
  [.items[] | select(.status.phase == "Running" or .status.phase == "Pending")
   | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $claim))]')
for owner in $(jq -r '.[].metadata.ownerReferences[]? | .kind + "/" + .name' <<<"$pods" | sort -u); do
  case $owner in
    ReplicaSet/*)
      owner=$(kubectl -n "$namespace" get "$owner" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}') ;;
  esac
  case $owner in
    Deployment/* | StatefulSet/*)
      echo "Scaling down $owner"
      kubectl -n "$namespace" scale "$owner" --replicas=0 ;;
    *)
      echo "$owner is using $claim; stop it, then run this again" >&2
      exit 1 ;;
  esac
done
for pod in $(jq -r '.[].metadata.name' <<<"$pods"); do
  kubectl -n "$namespace" wait --for=delete "pod/$pod" --timeout=10m
done

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

# Flux puts back the replica counts and spec.paused from Git.
echo "Resuming $kustomization"
trap - EXIT
flux resume kustomization "$kustomization"
