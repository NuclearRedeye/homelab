{ config, lib, pkgs, ... }:
{
  services.k3s = {
    enable = true;
    role = "server";

    # Pinned so lock file bumps only bring patch releases. Minor upgrades are
    # deliberate, one node at a time.
    package = pkgs.k3s_1_36;
    tokenFile = config.sops.secrets.k3s_token.path;

    # Cluster traffic (etcd, kubelet, flannel) uses the cluster VLAN
    nodeIP = (lib.head config.networking.interfaces.cluster.ipv4.addresses).address;

    extraFlags = [
      # Ingress and load balancing are chosen later, not bundled.
      "--disable=traefik"
      "--disable=servicelb"

      "--flannel-iface=cluster"

      # Encrypt Secrets at rest in etcd; secretbox over the aescbc default
      "--secrets-encryption"
      "--secrets-encryption-provider=secretbox"

      # Keep the hostname valid for kubectl over the LAN
      "--tls-san=${config.networking.hostName}"
    ];
  };

  # The API is open to the LAN for kubectl
  networking.firewall.allowedTCPPorts = [ 6443 ];

  # etcd, kubelet and flannel VXLAN only on the cluster VLAN
  networking.firewall.interfaces.cluster = {
    allowedTCPPorts = [ 2379 2380 10250 ];
    allowedUDPPorts = [ 8472 ];
  };

  # metrics-server reaches its own node's kubelet from the pod network
  networking.firewall.interfaces.cni0.allowedTCPPorts = [ 10250 ];
}
