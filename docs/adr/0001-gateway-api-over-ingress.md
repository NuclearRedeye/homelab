---
status: accepted
---

# Gateway API over Ingress

Cluster services are routed with Gateway API, through Traefik, not with Ingress. Ingress is frozen, and its behaviour lives in controller-specific annotations that nothing validates, so a typo silently drops a setting. Gateway API objects are validated CRDs, and a route's status says why it didn't attach.

The platform owns one `Gateway` in the `traefik` namespace, with its ports, listeners and certificates. Each app owns only its `HTTPRoute`s.

## Considered Options

- **Ingress:** rejected for the reasons above.
- **Traefik's `IngressRoute` CRDs:** validated, but specific to Traefik. Routes stay portable as `HTTPRoute`s; Traefik's CRDs are used only for `Middleware`, attached through `ExtensionRef` filters.

## Consequences

- The Gateway API CRDs are installed separately from the Traefik chart, and held to the version Traefik supports.
- Traefik's Ingress provider is off, so an Ingress created by a chart can't expose anything.
- An `ExtensionRef` can only reach a `Middleware` in the route's own namespace, so each app needs its own copy of any it uses.
