# Glossary

One-line explainers for the terms used across this repo.

## Hosts

- **NixOS**: a Linux distribution configured entirely from declarative Nix files.
- **Flake**: a Nix project with pinned inputs, so every build uses the same versions.
- **disko**: declares disk partitions in Nix and creates them during install.
- **sops-nix**: decrypts SOPS-encrypted secrets onto a host at boot.
- **Cluster VLAN**: VLAN 100, the private network the k3s nodes use to talk to each other.

## Cluster

- **k3s**: a lightweight Kubernetes distribution, run here on every node as a server.
- **etcd**: the database where Kubernetes keeps all cluster state.
- **Flannel**: k3s's default pod network, which links pods on different nodes.
- **VXLAN**: wraps pod traffic in UDP so it can cross the cluster VLAN between nodes.
- **Pod network**: the virtual network pods get their IPs from, separate from node IPs.
- **Host networking**: a pod using its node's network and IP instead of the pod network.
- **NetworkPolicy**: a Kubernetes rule limiting which pods can talk to which.
- **ValidatingAdmissionPolicy**: a built-in rule that rejects objects which break a policy.

## Delivery

- **Flux**: syncs the cluster with this repo, applying whatever is in Git.
- **Kustomize**: layers patches on top of plain Kubernetes YAML.
- **Helm chart**: a packaged, versioned set of Kubernetes manifests for one app.
- **Renovate**: opens PRs when a dependency in this repo has a new version.

## Traffic

- **MetalLB**: gives `LoadBalancer` Services a LAN IP, announced over ARP (L2 mode).
- **Gateway API**: the Kubernetes standard for routing outside traffic into the cluster.
- **Traefik**: the Gateway API controller that serves HTTP(S) into the cluster.
- **HTTPRoute**: maps a hostname and path to a Service through the Gateway.
- **cert-manager**: issues and renews TLS certificates as Kubernetes Secrets.
- **Authelia**: the single sign-on service that guards every route.
- **Forward-auth**: Traefik asks Authelia whether to allow each request before passing it on.

## Storage

- **DRBD**: a Linux kernel module that mirrors a block device to other nodes in real time.
- **LINSTOR**: manages DRBD volumes and their storage across nodes.
- **Piraeus**: the Kubernetes operator that installs and runs LINSTOR.
- **Controller**: the LINSTOR process that decides where volumes and replicas go.
- **Satellite**: the LINSTOR agent on each node that creates the local storage and DRBD devices.
- **HA Controller**: moves pods off a node when their volume loses quorum there.
- **Replica**: one node's copy of a replicated volume.
- **Quorum**: a majority of a volume's replicas must agree before it accepts writes.
- **LVM**: Linux's layer for carving disks into resizable logical volumes.
- **Thin pool**: an LVM pool that hands out space to volumes only as they write.
- **Volume group**: LVM's pool of one or more disks that logical volumes are cut from.
- **StorageClass**: tells Kubernetes how to create volumes, e.g. with three replicas.
