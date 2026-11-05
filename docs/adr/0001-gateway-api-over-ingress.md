---
status: accepted
---

# Gateway API over Ingress

Services are routed with Gateway API through Traefik, as its objects are validated CRDs and a route's status says why it didn't attach. The platform owns one `Gateway` in the `traefik` namespace; each app owns only its `HTTPRoute`s.

## Considered Options

- **Ingress:** rejected, as it's frozen and its behaviour lives in unvalidated, controller-specific annotations.
- **Traefik's `IngressRoute`:** rejected, as it ties routes to Traefik. Its CRDs are used only for `Middleware`, through `ExtensionRef` filters.

## Consequences

- The Gateway API CRDs are installed separately and held to the version Traefik supports.
- Traefik's Ingress provider is off, so a chart's Ingress can't expose anything.
