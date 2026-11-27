#!/usr/bin/env bash
# Builds kubeconform schemas from the CRDs that kubernetes/apps/ deploys, at their pinned
# versions, so a Renovate bump validates against what will actually run.
#   nix develop -c scripts/crd-schemas.sh <out-dir>
# Writes <out-dir>/<group>/<kind>_<version>.json. Expects cluster-settings
# placeholders in the environment, as validate.sh sets them.
set -euo pipefail

mkdir -p "$1"
out=$(realpath "$1")
cd "$(dirname "$0")/../kubernetes"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Picks one object out of a manifest stream, e.g. pick OCIRepository cert-manager.
pick() {
  yq "select(.kind == \"$1\" and .metadata.name == \"$2\")"
}

# Renders every HelmRelease's chart at its pinned version, with its own values,
# so CRDs that are templated or switched on by a value come out as deployed.
helm_crds() {
  for dir in $(grep -rl --include='*.yaml' 'kind: HelmRelease' apps | xargs -n1 dirname | sort -u); do
    local manifests="$work/manifests.yaml" values=()
    # The directory's own Flux Kustomization substitutions, e.g. pinned refs.
    mapfile -t values < <(yq ea "select(.kind == \"Kustomization\" and .spec.path == \"./kubernetes/$dir\")
      | .spec.postBuild.substitute // {} | to_entries | .[] | .key + \"=\" + .value" apps/*/ks.yaml)
    kustomize build "$dir" | env "${values[@]}" flux envsubst --strict > "$manifests"

    for name in $(yq 'select(.kind == "HelmRelease") | .metadata.name' "$manifests"); do
      local release namespace chart version
      release=$(pick HelmRelease "$name" < "$manifests")
      namespace=$(yq '.metadata.namespace' <<< "$release")
      yq '.spec.values // {}' <<< "$release" > "$work/values.yaml"

      if [[ $(yq '.spec.chartRef.kind' <<< "$release") == OCIRepository ]]; then
        local source
        source=$(pick OCIRepository "$(yq '.spec.chartRef.name' <<< "$release")" < "$manifests")
        chart=$(yq '.spec.url' <<< "$source")
        version=$(yq '.spec.ref.tag' <<< "$source")
        set -- "$chart"
      else
        local source
        source=$(pick HelmRepository "$(yq '.spec.chart.spec.sourceRef.name' <<< "$release")" < "$manifests")
        chart=$(yq '.spec.chart.spec.chart' <<< "$release")
        version=$(yq '.spec.chart.spec.version' <<< "$release")
        set -- "$chart" --repo "$(yq '.spec.url' <<< "$source")"
      fi

      echo "  $name $version" >&2
      helm template "$name" "$@" --version "$version" --namespace "$namespace" \
        --include-crds --values "$work/values.yaml"
      echo ---
    done
  done
}

# Reads the CRD files at each GitRepository's pinned tag, from the path its
# Flux Kustomization applies (Gateway API, snapshot CRDs).
git_crds() {
  # shellcheck disable=SC2013 # paths have no spaces; a read loop would share stdin with git
  for ks in $(grep -rl --include=ks.yaml 'kind: GitRepository' apps); do
    for name in $(yq 'select(.kind == "GitRepository") | .metadata.name' "$ks"); do
      local source url tag path clone="$work/git-$name"
      source=$(pick GitRepository "$name" < "$ks")
      url=$(yq '.spec.url' <<< "$source")
      tag=$(yq '.spec.ref.tag' <<< "$source")
      path=$(yq "select(.kind == \"Kustomization\" and .spec.sourceRef.name == \"$name\") | .spec.path" "$ks")

      echo "  $name $tag" >&2
      git clone --quiet --depth 1 --branch "$tag" --filter=blob:none --sparse "$url" "$clone" 2>/dev/null
      git -C "$clone" sparse-checkout set "$path"
      find "$clone/$path" -name '*.yaml' ! -name kustomization.yaml -exec sh -c 'cat "$1"; echo ---' _ {} \;
    done
  done
}

# Writes one schema file per CRD version.
to_schemas() {
  yq -o=json -I=0 'select(.kind == "CustomResourceDefinition")' \
    | jq -c -f ../scripts/crd-to-schema.jq \
    | while IFS= read -r entry; do
        local file
        file="$out/$(jq -r .file <<< "$entry")"
        mkdir -p "$(dirname "$file")"
        jq .schema <<< "$entry" > "$file"
      done
}

echo "Building schemas from deployed CRDs" >&2
{ helm_crds; git_crds; } | to_schemas
