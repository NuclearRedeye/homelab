# shellcheck shell=bash
# Shared by the scripts that act on volumes backed up by components/volsync.
# Source it; each function exits on a failure.

# Sets kustomization and volume for one of the service's backed-up volumes,
# defaulting to its only one.
#   find_volume SERVICE [VOLUME]
find_volume() {
  local service=$1 volumes
  volume=${2:-}
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
  # shellcheck disable=SC2034 # read by the sourcing script
  kustomization=$(jq -er --arg volume "$volume" '.[] | select(.volume == $volume) | .kustomization' <<<"$volumes") \
    || { echo "$service has no backed-up volume $volume" >&2; exit 1; }
}

# Prints the claim's ReplicationSource for the target, or every target's, one replicationsource/NAME per line.
#   replication_sources NAMESPACE CLAIM [TARGET]
replication_sources() {
  local namespace=$1 claim=$2 target=${3:-} sources
  if [[ -n $target ]]; then
    kubectl -n "$namespace" get "replicationsource/$claim-$target" >/dev/null \
      || { echo "no ReplicationSource $namespace/$claim-$target; is $target set up for $namespace?" >&2; exit 1; }
    echo "replicationsource/$claim-$target"
    return
  fi
  sources=$(kubectl -n "$namespace" get replicationsources -o json \
    | jq -r --arg claim "$claim" '.items[] | select(.spec.sourcePVC == $claim) | "replicationsource/" + .metadata.name')
  [[ -n $sources ]] || { echo "$claim has no ReplicationSources" >&2; exit 1; }
  echo "$sources"
}

# jq: a restic snapshot time, to the second in UTC, as restore.sh --restore-point takes it; the restore also ignores fractions.
# shellcheck disable=SC2016 # $time is a jq variable, nothing to expand
restore_time='def restore_time: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | . as $time | try (fromdate | todate) catch $time;'

# Prints the claim's backups and archives at the target, or every target, as one table, newest first.
# A time from it is a restore.sh --restore-point for that target.
#   list_backups NAMESPACE CLAIM [TARGET]
list_backups() {
  local namespace=$1 claim=$2 target=${3:-} sources rs
  sources=$(replication_sources "$namespace" "$claim" "$target")
  for rs in $sources; do
    rs=${rs#replicationsource/}
    # rclone can log to stderr too, which shares the pod log; restic prints the JSON as one line.
    run_restic "$namespace" "$rs" snapshots --json | grep '^\[' | tail -n 1 \
      | jq -r --arg source "${rs#"$claim"-}" "$restore_time"'
        def size: if . == null then "-" elif . >= 1073741824 then "\(. / 1073741824 * 10 | round / 10) GiB"
          else "\(. / 1048576 | round) MiB" end;
        .[]
        | [(.time | restore_time), $source, .short_id, (.summary.total_bytes_processed | size),
           # Only archives have names; backup.sh --archive moves them to host archive.
           (if .hostname == "archive" then .tags // [] | join(",") else "" end)]
        | @tsv'
  done | sort -r | { printf 'TIME\tSOURCE\tSNAPSHOT\tSIZE\tNAME\n'; cat; } | column -t -s $'\t'
}

# Scales down whatever is running with the claim mounted, and waits for its pods to go.
# Suspend the Flux Kustomization first, or Flux scales them back up.
#   stop_claim_users NAMESPACE CLAIM
stop_claim_users() {
  local namespace=$1 claim=$2 pods owner pod
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
}

# Runs restic in a one-off Job against the ReplicationSource's repository, and prints its output.
# The Job mirrors the mover's Secret, volumes and security context, so credentials stay in the cluster.
#   run_restic NAMESPACE REPLICATIONSOURCE RESTIC_ARGS...
run_restic() (
  local namespace=$1 rs=$2 rs_json image job conditions logs lock
  shift 2
  # Reads skip the lock so they don't block a backup; writes must take it, and forget refuses --no-lock.
  case $1 in snapshots | ls | stats | cat | find | diff) lock=(--no-lock) ;; *) lock=() ;; esac
  rs_json=$(kubectl -n "$namespace" get replicationsource "$rs" -o json)
  # Same image as VolSync's movers, so restic and rclone match the nightly backups.
  image=$(kubectl -n volsync get deployments -o json | jq -er '
    [.items[].spec.template.spec.containers[].args[]? | select(startswith("--restic-container-image="))
     | ltrimstr("--restic-container-image=")] | first') \
    || { echo "couldn't find VolSync's restic image" >&2; exit 1; }
  # shellcheck disable=SC2016 # $mover and $volumes are yq variables, nothing to expand
  job=$(APP=$namespace REPLICATION_SOURCE=$rs RESTIC_IMAGE=$image \
    flux envsubst --strict <"$(dirname "${BASH_SOURCE[0]}")/../../kubernetes/components/volsync/templates/restic-job.yaml" \
    | rs=$rs_json args=$(jq -nc '$ARGS.positional' --args -- "${lock[@]}" "$@") yq '
        env(rs).spec.restic as $mover | ($mover.moverVolumes // []) as $volumes
        | .spec.template.spec.securityContext = $mover.moverSecurityContext
        | .spec.template.spec.volumes = [$volumes[] | {"name": .mountPath} + .volumeSource]
        | .spec.template.spec.containers[0] |= (
            .command += env(args)
            | .envFrom = [{"secretRef": {"name": $mover.repository}}]
            # Where VolSync mounts moverVolumes, so paths in the Secret work the same.
            | .volumeMounts = [$volumes[] | {"name": .mountPath, "mountPath": "/mnt/" + .mountPath}])' \
    | kubectl create -f - -o name)
  trap 'kubectl -n "$namespace" delete "$job" --wait=false >/dev/null' EXIT
  # Polls, as kubectl wait can't wait for either of two conditions.
  while :; do
    conditions=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.conditions[?(@.status=="True")].type}')
    case " $conditions " in
      *" Complete "*) kubectl -n "$namespace" logs "$job"; break ;;
      *" Failed "*)
        logs=$(kubectl -n "$namespace" logs "$job" 2>&1) || true
        echo "$logs" >&2
        echo "restic $* failed against $namespace/$rs's repository" >&2
        # Writes fail at once rather than wait for the lock.
        if grep -q 'repository is already locked' <<<"$logs"; then
          echo "it's locked, probably by a running backup, forget or prune; try again later" >&2
        fi
        exit 1 ;;
    esac
    sleep 2
  done
)
