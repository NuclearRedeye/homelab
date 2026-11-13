{ config, lib, pkgs, ... }:
{
  services.k3s = {
    enable = true;
    role = "server";

    # Pinned so lock file bumps only bring patch releases. Minor upgrades are
    # deliberate, one node at a time.
    package = pkgs.k3s_1_36;
    tokenFile = config.sops.secrets.k3s_token.path;

    # Rendered at boot so the API VIP stays out of this public repo
    configPath = config.sops.templates."k3s.yaml".path;

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
    ];
  };

  sops.secrets.api_vip.sopsFile = ../../secrets/k3s.yaml;

  # Hostname and VIP stay valid for kubectl over the LAN. In the file, not as
  # --tls-san flags, which would replace its whole list.
  sops.templates."k3s.yaml" = {
    content = ''
      tls-san:
        - ${config.networking.hostName}
        - ${config.sops.placeholder.api_vip}
    '';
    restartUnits = [ "k3s.service" ];
  };

  # The API is open to the LAN for kubectl
  networking.firewall.allowedTCPPorts = [ 6443 ];

  # etcd, kubelet, flannel VXLAN and MetalLB memberlist only on the cluster VLAN
  networking.firewall.interfaces.cluster = {
    allowedTCPPorts = [ 2379 2380 7946 10250 ];
    allowedUDPPorts = [ 7946 8472 ];
  };

  # metrics-server reaches its own node's kubelet from the pod network
  networking.firewall.interfaces.cni0.allowedTCPPorts = [ 10250 ];
}
