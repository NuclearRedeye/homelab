---
status: accepted
---

# Deployment patterns

Each app is deployed one of three ways, chosen by its role, so the repo stays consistent:

- **Platform capabilities**, which other services rely on (e.g. Traefik, cert-manager, Authelia, Longhorn), use the vendor's own chart, or its raw manifests if it has none.
- **Workloads** (e.g. Home Assistant, UniFi Network) use [`bjw-s/app-template`](https://github.com/bjw-s/helm-charts), one values file per app, even when an official chart exists.
- **One-off objects** (e.g. the `Gateway`, issuers) are plain YAML.

## Considered Options

- **Platform defined by mechanism** (CRDs, controllers, node agents): rejected, as Authelia has none yet is a platform capability.
- **Official charts wherever they exist:** rejected, as every app would take a different shape.
- **Plain manifests for workloads:** rejected, as near-identical YAML per app drifts apart.
- **Third-party chart collections** (Bitnami, TrueCharts, k8s-at-home): rejected, as they repackage others' software.

## Consequences

- A major app-template release changes every workload's values in one PR.
