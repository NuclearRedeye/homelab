---
status: accepted
---

# Per-route auth, enforced by admission

Every `HTTPRoute` requires an Authelia login, wherever the client is, LAN included. Forward-auth is attached per route, so public sites keep working when Authelia is down. A `ValidatingAdmissionPolicy` rejects any route without it, unless the route opts out explicitly with `homelab/public: "true"`.

## Considered Options

- **Forward-auth on the entry point:** rejected, as an Authelia outage would take down public sites too.
- **Per route, checked in CI:** rejected, as a missed route is open until CI catches it, and CI never sees `kubectl apply`.
- **Separate public and private Gateways:** rejected, as the router can only forward 80 and 443 to one address.

## Consequences

- Each app namespace needs its own forward-auth `Middleware`, as an `ExtensionRef` can't cross namespaces.
- `grep -r 'homelab/public'` lists every public route.
