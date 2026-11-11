#!/usr/bin/env bash
# Validates kubernetes/ as Flux will build it. Run inside the dev shell:
#   nix develop -c kubernetes/validate.sh
# Based on fluxcd/flux2-kustomize-helm-example's scripts/validate.sh.
set -euo pipefail

cd "$(dirname "$0")"

echo "Checking secrets are encrypted"
find . -name '*.yaml' -print0 | xargs -0 ./check-encryption.sh

# Schemas for the Flux version in the repo, not the CLI's, so Renovate bumps
# validate against what will actually run.
version=$(sed -n 's/^# Flux Version: //p' flux-system/gotk-components.yaml)
schemas=$(mktemp -d)
trap 'rm -rf "$schemas"' EXIT
mkdir -p "$schemas/master-standalone-strict"
curl -sSfL "https://github.com/fluxcd/flux2/releases/download/${version}/crd-schemas.tar.gz" \
  | tar zxf - -C "$schemas/master-standalone-strict"

# Schemas for other custom resources, matched by API version. Pinned so results
# match on every machine; Renovate bumps the commit.
crd_catalog_ref=49729e49e8f062933e3716a26540d41b0cd0856c
crd_catalog="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${crd_catalog_ref}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# Placeholders for cluster-settings, so substituted fields still validate.
# Add one per key in settings.sops.yaml; --strict fails on any that are missing.
export METALLB_POOL=192.168.0.1/16
export TRAEFIK_IP=192.168.0.1
export CYBERTRON_DOMAIN=example.com
export JUNKION_DOMAIN=example.net
export QUINTESSA_DOMAIN=example.org

# Flux leaves a missing setting empty, so every ${VAR} in apps/ and components/ must be a real key.
for var in $(grep -rhoE '\$\{[A-Z0-9_]+\}' apps components | tr -d '${}' | sort -u); do
  grep -qE "^[[:space:]]*$var:" settings/app/settings.sops.yaml || { echo "no setting for \${$var}" >&2; exit 1; }
done

# Approximates Flux: substitutes all of apps/ and components/, though Flux only does so where a
# Kustomization has substituteFrom. gotk-components.yaml has a literal ${var}.
substitute() {
  if [[ "$1" == ./apps/* || "$1" == ./components/* ]]; then flux envsubst --strict; else cat; fi
}

# Secrets are skipped as their sops metadata fails strict validation, and CRDs
# as upstream ships them and no schema exists. Unknown kinds still fail.
# HACK(#132): The catalog's Piraeus schemas don't compile; skip them until datreeio/CRDs-catalog#1012 merges.
skip=Secret,CustomResourceDefinition,LinstorCluster,LinstorSatelliteConfiguration
find . -name kustomization.yaml -print0 | while IFS= read -r -d '' file; do
  dir=$(dirname "$file")
  echo "Validating $dir"
  kustomize build "$dir" \
    | substitute "$dir" \
    | kubeconform -strict -summary -skip "$skip" \
        -schema-location default -schema-location "$schemas" \
        -schema-location "$crd_catalog"
done
