{ config, lib, pkgs, ... }:
let
  # Host-specific network facts. At the VLAN 11 cutover, change these
  # (and the IP lines in the env files), then redeploy.
  lan = {
    name = "dns-lan";
    parent = "enp0s25";
    subnet = "192.168.11.0/24";
    gateway = "192.168.11.1";
  };

  # The stack definition lives in the repo, outside the NixOS config.
  # Interpolating this path copies the directory into the Nix store.
  stackDir = ../../services/core/pihole;
  base = "/srv";
  docker = config.virtualisation.docker.package;
  compose = "${docker}/bin/docker compose -f ${stackDir}/compose.yaml";

  # One entry per Pi-hole instance. Each needs .env.<name> in the stack dir.
  instances = [ "trusted" "restricted" ];

  mkInstance = name:
    let up = "${compose} --env-file ${stackDir}/.env.${name} up -d";
    in lib.nameValuePair "pihole-${name}" {
      description = "Pi-hole (${name})";
      requires = [ "docker.service" "docker-network-dns-lan.service" ];
      after = [ "docker.service" "docker-network-dns-lan.service" ];
      wantedBy = [ "multi-user.target" ];
      reloadIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
        ExecStart = up;
        ExecReload = up;
        ExecStop = "${compose} --env-file ${stackDir}/.env.${name} down";
      };
    };
in
{
  # The compose files mount /etc/timezone; NixOS doesn't create it.
  environment.etc."timezone".text = "${config.time.timeZone}\n";

  # Data directories for the bind mounts (BASE/USER_NAME/config).
  systemd.tmpfiles.rules = lib.concatMap (name: [
      "d ${base}/pihole-${name} 0755 root root -"
      "d ${base}/pihole-${name}/config 0755 root root -"
    ]) instances;

  systemd.services = {
    # Create the macvlan network once per host, outside the compose file.
    docker-network-dns-lan = {
      description = "Docker macvlan network ${lan.name}";
      requires = [ "docker.service" ];
      after = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        have=$(docker network inspect ${lan.name} \
          --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)
        if [ "$have" != "${lan.subnet}" ]; then
          docker network rm ${lan.name} 2>/dev/null || true
          docker network create -d macvlan \
            --subnet=${lan.subnet} --gateway=${lan.gateway} \
            -o parent=${lan.parent} ${lan.name}
        fi
      '';
    };
  } // lib.listToAttrs (map mkInstance instances);
}
