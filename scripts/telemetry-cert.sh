#!/usr/bin/env bash
# Issues the mTLS certificates that telemetry scrapes use, from an offline CA.
#
# Usage: telemetry-cert.sh ca | host NAME | client NAME
#   ca           creates the CA: its key in secrets/telemetry-ca.yaml, its
#                certificate in nixos/keys/telemetry-ca.crt
#   host NAME    signs a server certificate for NAME.$LAN_DOMAIN into secrets/NAME.yaml
#   client NAME  signs a client certificate for NAME into a Secret in
#                kubernetes/apps/victoria-metrics/app/NAME-tls.sops.yaml
#
# Everything lasts 100 years and is issued once; nothing ever renews. Each
# command refuses to replace what it would write. LAN_DOMAIN is read from
# cluster-settings, so it stays out of this public repo.
set -euo pipefail

usage() {
  sed -n '2,/^set /{/^#/s/^# \{0,1\}//p;}' "$0" >&2
  exit 2
}

cd "$(dirname "$0")/.."

ca_secrets=secrets/telemetry-ca.yaml
ca_cert=nixos/keys/telemetry-ca.crt
days=36500

# Keys only touch disk here, outside the repo, and are gone on exit.
umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# True if a sops file holds the given index, e.g. has secrets/snarl.yaml '["x"]'.
has() {
  [[ -f $1 ]] && sops decrypt --extract "$2" "$1" > /dev/null 2>&1
}

# Stores a file's contents at a top-level key, creating the sops file if needed.
store() {
  local file=$1 key=$2 value=$3
  if [[ -f $file ]]; then
    jq -Rs . < "$value" | sops set --value-stdin "$file" "[\"$key\"]"
  else
    jq -n --arg k "$key" --rawfile v "$value" '{($k): $v}' \
      | sops encrypt --filename-override "$file" --input-type json --output "$file"
  fi
}

# Signs a P-256 key and certificate into $work/NAME.{key,crt}, with the given SAN and usage.
sign() {
  local name=$1 san=$2 usage=$3
  sops decrypt --extract '["ca_key"]' "$ca_secrets" > "$work/ca.key"
  openssl req -x509 -new -noenc -days "$days" \
    -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -keyout "$work/$name.key" -out "$work/$name.crt" \
    -CA "$ca_cert" -CAkey "$work/ca.key" \
    -subj "/CN=$name" \
    -addext "subjectAltName=$san" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=$usage"
}

ca() {
  if [[ -f $ca_secrets || -f $ca_cert ]]; then
    echo "the CA already exists; reissuing it means reissuing every certificate" >&2
    exit 1
  fi
  openssl req -x509 -new -noenc -days "$days" \
    -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
    -keyout "$work/ca.key" -out "$work/ca.crt" \
    -subj "/CN=homelab telemetry CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
  store "$ca_secrets" ca_key "$work/ca.key"
  cp "$work/ca.crt" "$ca_cert"
  echo "wrote $ca_secrets and $ca_cert" >&2
}

host() {
  local name=$1 file=secrets/$1.yaml domain
  if has "$file" '["node_exporter_key"]'; then
    echo "$file already has a node-exporter certificate" >&2
    exit 1
  fi
  domain=$(sops decrypt --extract '["stringData"]["LAN_DOMAIN"]' kubernetes/settings/app/settings.sops.yaml)
  sign "$name" "DNS:$name.$domain" serverAuth
  store "$file" node_exporter_key "$work/$name.key"
  store "$file" node_exporter_cert "$work/$name.crt"
  echo "wrote $file" >&2
}

client() {
  local name=$1 file=kubernetes/apps/victoria-metrics/app/$1-tls.sops.yaml
  if [[ -f $file ]]; then
    echo "$file already exists" >&2
    exit 1
  fi
  sign "$name" "DNS:$name" clientAuth
  mkdir -p "$(dirname "$file")"
  jq -n --arg name "$name-tls" \
    --rawfile crt "$work/$name.crt" --rawfile key "$work/$name.key" --rawfile ca "$ca_cert" \
    '{apiVersion: "v1", kind: "Secret", type: "kubernetes.io/tls",
      metadata: {name: $name, namespace: "victoria-metrics"},
      stringData: {"tls.crt": $crt, "tls.key": $key, "ca.crt": $ca}}' \
    | sops encrypt --filename-override "$file" --input-type json --output "$file"
  echo "wrote $file" >&2
}

case ${1:-} in
  ca) [[ $# -eq 1 ]] || usage; ca ;;
  host) [[ $# -eq 2 ]] || usage; host "$2" ;;
  client) [[ $# -eq 2 ]] || usage; client "$2" ;;
  *) usage ;;
esac
