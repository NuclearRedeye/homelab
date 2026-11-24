#!/usr/bin/env bash
# Validates kubernetes/ as Flux will build it. Run inside the dev shell:
#   nix develop -c scripts/validate.sh
# Based on fluxcd/flux2-kustomize-helm-example's scripts/validate.sh.
set -euo pipefail

cd "$(dirname "$0")/../kubernetes"

echo "Checking secrets are encrypted"
find . -name '*.yaml' -print0 | xargs -0 ../scripts/check-encryption.sh

# Schemas for the Flux version in the repo, not the CLI's, so Renovate bumps
# validate against what will actually run.
version=$(sed -n 's/^# Flux Version: //p' flux-system/gotk-components.yaml)
schemas=$(mktemp -d)
trap 'rm -rf "$schemas"' EXIT
mkdir -p "$schemas/master-standalone-strict"
curl -sSfL "https://github.com/fluxcd/flux2/releases/download/${version}/crd-schemas.tar.gz" \
  | tar zxf - -C "$schemas/master-standalone-strict"

# Placeholders for cluster-settings, so substituted fields still validate.
# Add one per key in settings.sops.yaml.
declare -A placeholders=(
  [METALLB_POOL]=192.168.0.1/16
  [TRAEFIK_IP]=192.168.0.1
  [API_VIP]=192.168.0.2
  [CYBERTRON_DOMAIN]=example.com
  [JUNKION_DOMAIN]=example.net
  [QUINTESSA_DOMAIN]=example.org
)
settings=$(sed -nE 's/^[[:space:]]+([A-Z0-9_]+):.*/\1/p' settings/app/settings.sops.yaml)
flags=$(yq -o=json '.data' settings/app/flags.yaml)

# Schemas for other custom resources, built from the CRDs we deploy (#178).
placeholder_env=()
for var in "${!placeholders[@]}"; do placeholder_env+=("$var=${placeholders[$var]}"); done
env "${placeholder_env[@]}" ../scripts/crd-schemas.sh "$schemas/crds"

# Secrets are skipped as their sops metadata fails strict validation, and CRDs
# as upstream ships them and no schema exists. Unknown kinds still fail.
skip=Secret,CustomResourceDefinition
validate() {
  kubeconform -strict -summary -skip "$skip" \
    -schema-location default -schema-location "$schemas" \
    -schema-location "$schemas/crds/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
}

# Each Flux Kustomization on this repo, with its path and the values it substitutes.
kustomizations=$(kustomize build . | yq -o=json -I=0 '
  select(.apiVersion == "kustomize.toolkit.fluxcd.io/v1" and .kind == "Kustomization"
    and .spec.sourceRef.name == "flux-system")
  | {"name": .metadata.name,
     "path": (.spec.path | sub("^\./kubernetes"; ".")),
     "settings": ([.spec.postBuild.substituteFrom[]? | select(.name == "cluster-settings")] | length > 0),
     "flags": ([.spec.postBuild.substituteFrom[]? | select(.name == "cluster-flags")] | length > 0),
     "values": (.spec.postBuild.substitute // {})}')
paths=$(jq -r .path <<<"$kustomizations")

# Directories no Flux Kustomization points at build as they are. Components need
# an app's values, so they're checked through the apps that include them.
find . -name kustomization.yaml -print0 | while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  grep -qxF "$dir" <<<"$paths" && continue
  [[ $(yq '.kind' "$file") == Component ]] && continue
  echo "Validating $dir"
  kustomize build "$dir" | validate
done

# Templates the scripts fill in and apply, so a chart upgrade that breaks one fails here.
find . -path '*/templates/*.yaml' -print0 | while IFS= read -r -d '' template; do
  echo "Validating $template"
  env=()
  # shellcheck disable=SC2016 # strips the literal ${} characters, nothing to expand
  for var in $(grep -oE '\$\{[A-Z0-9_]+\}' "$template" | tr -d '${}' | sort -u); do env+=("$var=example"); done
  env "${env[@]}" flux envsubst --strict <"$template" | validate
done

# Flux leaves a missing value empty, so each ${VAR} must come from the Kustomization's
# own substitute or, if it uses them, the flags or settings.
while IFS= read -r ks; do
  name=$(jq -r .name <<<"$ks")
  path=$(jq -r .path <<<"$ks")
  echo "Validating $path ($name)"
  build=$(kustomize build "$path")
  env=()
  # shellcheck disable=SC2016 # strips the literal ${} characters, nothing to expand
  for var in $(grep -oE '\$\{[A-Z0-9_]+\}' <<<"$build" | tr -d '${}' | sort -u); do
    if value=$(jq -er --arg var "$var" '.values[$var] // empty' <<<"$ks"); then
      env+=("$var=$value")
    elif [[ $(jq -r .flags <<<"$ks") == true ]] && value=$(jq -er --arg var "$var" '.[$var] // empty' <<<"$flags"); then
      env+=("$var=$value")
    elif [[ $(jq -r .settings <<<"$ks") == true ]] && grep -qxF "$var" <<<"$settings"; then
      [[ -v placeholders[$var] ]] || { echo "no placeholder for \${$var} in validate.sh" >&2; exit 1; }
      env+=("$var=${placeholders[$var]}")
    else
      echo "$name: no value for \${$var}" >&2
      exit 1
    fi
  done
  if [[ ${#env[@]} -eq 0 ]]; then
    validate <<<"$build"
  else
    env "${env[@]}" flux envsubst --strict <<<"$build" | validate
  fi
done <<<"$kustomizations"
