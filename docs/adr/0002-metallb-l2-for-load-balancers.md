---
status: accepted
---

# MetalLB in L2 mode for load balancers

`LoadBalancer` Services get a stable address from MetalLB in L2 mode, from a pool on the trusted VLAN outside DHCP. It needs nothing from the router, and fails over in about 7 s.

## Considered Options

- **k3s ServiceLB:** rejected, as it opens ports on each node's own address, so a hostname must point at specific nodes.
- **kube-vip for Services:** rejected, as it also needs kube-vip-cloud-provider.
- **MetalLB BGP mode:** rejected for now, as the pool would need its own subnet routed through the router, configured outside Git. Under investigation in #110.

## Consequences

- One node carries all traffic for each address.
- Services that need the client IP or fast failover use `externalTrafficPolicy: Local` with a pod on every node, avoiding a ~72 s tail.
- The `L2Advertisement` names the LAN interface, so nothing is announced on the cluster VLAN.
- One pool address is reserved for a future API server VIP.
