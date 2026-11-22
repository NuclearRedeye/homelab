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

# Prints every target's ReplicationSource for the claim, one replicationsource/NAME per line.
#   replication_sources NAMESPACE CLAIM
replication_sources() {
  kubectl -n "$1" get replicationsources -o json \
    | jq -r --arg claim "$2" '.items[] | select(.spec.sourcePVC == $claim) | "replicationsource/" + .metadata.name'
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
