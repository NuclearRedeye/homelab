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

  # How long an instance may take to answer after a reload before it counts
  # as unhealthy. Containers are recreated on an env change, so this needs
  # to cover a cold FTL start.
  settleSeconds = 90;

  stamp = "/var/lib/pihole-health/rolled-back-from";

  # Probe pi.hole, which FTL answers itself: an external name would make an
  # internet outage trigger a pointless rollback. Addressing containers by
  # name rather than IP also keeps the Pi-hole addresses in sops, where A5
  # put them.
  probe = pkgs.writeShellScript "pihole-probe" ''
    set -u
    failed=0
    for name in ${lib.concatStringsSep " " instances}; do
      answer=""
      waited=0
      while [ "$waited" -lt ${toString settleSeconds} ]; do
        answer=$(${docker}/bin/docker exec "pihole-$name" \
          dig +short +time=2 +tries=1 pi.hole @127.0.0.1 2>/dev/null || true)
        [ "$answer" = "127.0.0.1" ] && break
        sleep 3
        waited=$(( waited + 3 ))
      done
      if [ "$answer" = "127.0.0.1" ]; then
        echo "pihole-$name: healthy after ''${waited}s"
      else
        echo "pihole-$name: no answer for pi.hole after ${toString settleSeconds}s" >&2
        failed=1
      fi
    done

    # Rearm the flap guard once healthy, so one rollback years ago does not
    # suppress every future one.
    if [ "$failed" -eq 0 ]; then
      rm -f "${stamp}"
    fi
    exit "$failed"
  '';

  # Roll back one generation, once. The stamp is the flap guard: if the
  # previous generation is broken too, stop and leave the box for a human
  # rather than walking backwards through generations.
  rollback = pkgs.writeShellScript "pihole-rollback" ''
    set -eu
    if [ -e "${stamp}" ]; then
      echo "unhealthy, but already rolled back from $(cat ${stamp}); staying put" >&2
      exit 1
    fi

    from=$(readlink /nix/var/nix/profiles/system)
    echo "$from" > "${stamp}"
    echo "rolling back from $from" >&2

    ${config.nix.package}/bin/nix-env --rollback --profile /nix/var/nix/profiles/system
    /nix/var/nix/profiles/system/bin/switch-to-configuration switch

    if ${probe}; then
      echo "rollback restored DNS; main still carries the bad change" >&2
    else
      echo "previous generation is also unhealthy; manual intervention needed" >&2
    fi
    exit 1
  '';

  mkInstance = name:
    let up = "${compose} --env-file ${envFile name} up -d";
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

  # Data directories for the bind mounts (BASE/USER_NAME/config), plus the
  # directory holding the flap guard stamp.
  systemd.tmpfiles.rules = [
      "d /var/lib/pihole-health 0700 root root -"
    ] ++ lib.concatMap (name: [
      "d ${base}/pihole-${name} 0755 root root -"
      "d ${base}/pihole-${name}/config 0755 root root -"
    ]) instances;

  systemd.services = {
    # Probe after an unattended upgrade, via the gate unit so that its own
    # onFailure drives the rollback. Deliberately not onFailure on this unit:
    # that fires on evaluation, build and network failures too, where nothing
    # was activated and rolling back would discard a working generation for
    # no reason. ExecStartPost only runs when the switch itself succeeded.
    nixos-upgrade = lib.mkIf config.system.autoUpgrade.enable {
      serviceConfig.ExecStartPost = [
        "${pkgs.systemd}/bin/systemctl restart pihole-health.service"
      ];
    };

    # Health gate at boot. The same probe runs post-upgrade via ExecStartPost
    # on nixos-upgrade.service.
    pihole-health = {
      description = "Pi-hole health gate";
      after = map (name: "pihole-${name}.service") instances;
      # wants, not requires: a Requires= dependency that fails prevents this
      # unit from starting at all, which is precisely the case the gate exists
      # to catch.
      wants = map (name: "pihole-${name}.service") instances;
      wantedBy = [ "multi-user.target" ];
      onFailure = [ "pihole-rollback.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "${toString (settleSeconds * 2)}s";
        ExecStart = "${probe}";
      };
    };

    pihole-rollback = {
      description = "Roll back after a failed Pi-hole health gate";
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
        ExecStart = "${rollback}";
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
