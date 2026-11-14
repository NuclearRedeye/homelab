---
status: accepted
---

# Piraeus and DRBD for replicated volumes

Stateful pods need volumes that survive their node failing, on three NUCs with two cores and one shared 1GbE port each. We chose Piraeus (LINSTOR) with DRBD 9, keeping 3 replicas on an LVM-thin pool on each node's 850 EVO, because it fits that hardware (about 270–880MiB of RAM per node, measured in #121) and fails over without data loss (#122). NixOS provides the DRBD kernel module, not the operator, so the module is built and versioned like the rest of the host.

## Considered Options

- **Longhorn v1:** kept as the fallback. It recommends 4 cores per node and runs each volume's data path in userspace processes, where DRBD's is in the kernel. #121 showed the shared port is the limit, so Longhorn wouldn't be faster either.
- **Longhorn v2, Mayastor, Simplyblock, Rook-Ceph:** rejected, as they need dedicated cores, hugepages or 10GbE.
- **DRBD managed by hand in NixOS, or with Pacemaker:** rejected, as each volume would need host config, and Kubernetes couldn't create or move volumes itself.

## Consequences

- A kernel update can fail to build the out-of-tree module (#36), and a new module only loads after a reboot, which auto-upgrade doesn't do.
- Each commit waits for two remote copies over the shared port, about 3.5ms more than a local disk.
- After a power loss, a pod waits about 7 minutes for Kubernetes to release its volume, unless the node is tainted `out-of-service`.
- Losing two nodes freezes I/O on the last copy rather than failing it.
- Backups are separate: replicas protect against a node failing, not against deletion or corruption.
