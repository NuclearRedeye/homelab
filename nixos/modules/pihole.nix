{ config, lib, pkgs, ... }:
let
  # Only the facts Nix needs at evaluation time. The subnet and gateway are
  # read from /run/secrets/pihole-net at runtime so they stay out of the store.
  lan = {
    name = "dns-lan";
    parent = "enp0s25";
  };

  # The stack definition lives in the repo, outside the NixOS config.
  # Interpolating this path copies the directory into the Nix store.
  stackDir = ../../services/core/pihole;
  base = "/srv";
  docker = config.virtualisation.docker.package;
  compose = "${docker}/bin/docker compose -f ${stackDir}/compose.yaml";

  # One entry per Pi-hole instance. Each needs a pihole-env-<name> secret.
  instances = [ "trusted" "restricted" ];

  envFile = name: config.sops.secrets."pihole-env-${name}".path;

  # How long a container may take to report healthy. An env change recreates
  # it, so this has to cover a cold FTL start.
  settleSeconds = 90;

  mkInstance = name:
    let
      # --wait blocks until compose reports the service running|healthy and
      # exits non-zero otherwise, so a switch cannot report success over a
      # container that never came up. The image's HEALTHCHECK is
      #   dig +short +norecurse +retry=0 @127.0.0.1 pi.hole
      # so it proves FTL is answering locally. It says nothing about the
      # upstreams or the macvlan, and nothing acts on a failure automatically:
      # the unit just fails, and DNS going down is its own alarm.
      up = "${compose} --env-file ${envFile name} up -d --wait --wait-timeout ${toString settleSeconds}";
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
        ExecStop = "${compose} --env-file ${envFile name} down";
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
        set -a
        . ${config.sops.secrets."pihole-net".path}
        set +a

        have=$(docker network inspect ${lan.name} \
          --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)
        if [ "$have" != "$SUBNET" ]; then
          docker network rm ${lan.name} 2>/dev/null || true
          docker network create -d macvlan \
            --subnet="$SUBNET" --gateway="$GATEWAY" \
            -o parent=${lan.parent} ${lan.name}
        fi
      '';
    };
  } // lib.listToAttrs (map mkInstance instances);
}
