{ config, lib, pkgs, ... }:
{
  services.k3s = {
    enable = true;
    role = "server";

    # Pinned so lock file bumps only bring patch releases. Minor upgrades are
    # deliberate, one node at a time.
    package = pkgs.k3s_1_36;
    tokenFile = config.sops.secrets.k3s_token.path;

    # Ingress and load balancing are chosen later, not bundled.
    extraFlags = [ "--disable=traefik" "--disable=servicelb" ];
  };

  # API, etcd peers and kubelet; UDP is flannel's VXLAN between nodes.
  networking.firewall.allowedTCPPorts = [ 6443 2379 2380 10250 ];
  networking.firewall.allowedUDPPorts = [ 8472 ];
}
