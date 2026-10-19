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

  instanceUnits = map (name: "pihole-${name}.service") instances;

  mkInstance = name:
    let
      # --wait blocks until compose reports the service running|healthy and
      # exits non-zero otherwise, so the unit's own state is the health
      # signal. The HEALTHCHECK comes from the Pi-hole image; defining our
      # own probe here would only be a worse guess at what FTL being up means.
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
    # Probe after an unattended upgrade. Deliberately not onFailure on this
    # unit: that also fires on evaluation, build and network failures, where
    # nothing was activated and rolling back would discard a working
    # generation for no reason. ExecStartPost runs only if the switch
    # itself succeeded.
    nixos-upgrade = lib.mkIf config.system.autoUpgrade.enable {
      serviceConfig.ExecStartPost = [
        "${config.systemd.package}/bin/systemctl restart pihole-health.service"
      ];
    };

    # The gate. Because the instance units wait for healthy, their own state
    # is the whole answer, so this is just a status check.
    pihole-health = {
      description = "Pi-hole health gate";
      after = instanceUnits;
      # wants, not requires: a Requires= dependency that fails prevents this
      # unit from starting at all, which is precisely the case the gate
      # exists to catch.
      wants = instanceUnits;
      wantedBy = [ "multi-user.target" ];
      onFailure = [ "pihole-rollback.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.systemd.package}/bin/systemctl is-active --quiet ${lib.concatStringsSep " " instanceUnits}";
      };
    };

    pihole-rollback = {
      description = "Roll back after a failed Pi-hole health gate";
      # systemd's own rate limit is the flap guard: at most one rollback an
      # hour, so a previous generation that is also broken cannot walk us
      # backwards through generations.
      unitConfig = {
        StartLimitIntervalSec = "1h";
        StartLimitBurst = 1;
      };
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
        # Sequential, and oneshot stops at the first failure, so a failed
        # rollback cannot fall through to re-activating the broken generation.
        ExecStart = [
          "${config.nix.package}/bin/nix-env --rollback --profile /nix/var/nix/profiles/system"
          "/nix/var/nix/profiles/system/bin/switch-to-configuration switch"
        ];
      };
    };

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
