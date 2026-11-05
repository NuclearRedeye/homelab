---
status: accepted
---

# MetalLB in L2 mode for load balancers

`LoadBalancer` Services get stable LAN addresses from MetalLB in L2 mode, from a fixed pool on the trusted VLAN outside the router's DHCP range. k3s's ServiceLB is disabled. L2 needs nothing from the router, and failover in about 7 s is fast enough for a homelab.

## Considered Options

- **k3s ServiceLB:** rejected. It opens each Service's port on every node's own address, so a hostname must point at specific nodes. A service should have one address that follows it between nodes.
- **kube-vip for Services:** rejected. It needs kube-vip-cloud-provider as well, one more component to own.
- **MetalLB BGP mode:** rejected for now. The pool would need its own subnet routed by the router, so all LAN traffic to it would pass through the router, and the router config would live outside Git. Its gains, spreading load across nodes and faster failover, aren't needed at this size. Being investigated in #110.

## Consequences

- In L2 mode one node answers for each address, so that node carries all of its traffic.
- Services that need the client IP, or fast failover, use `externalTrafficPolicy: Local` with a pod on every node. With `Cluster`, endpoints on a failed node linger for about 72 s after the address has moved.
- The `L2Advertisement` names the LAN interface, so MetalLB never answers ARP on the unrouted cluster VLAN.
- One pool address is reserved for a future API server VIP. kube-vip may be added for that alone, with its Service support off.
