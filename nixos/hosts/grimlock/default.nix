{ config, lib, pkgs, ... }:
{
  imports = [ ./disko.nix ../../modules/base.nix ../../modules/pihole.nix ];

  networking.hostName = "grimlock";
  networking.useDHCP = lib.mkDefault true;

  # Resolve via the EdgeRouter, never our own Pi-hole containers
  networking.nameservers = [ "192.168.11.1" ];

  # Prevent DHCP overwriting nameservers
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  # Hardware: Broadwell NUC (SATA = AHCI, USB 3 = xHCI)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Bootloader: UEFI + systemd-boot, keep the last 10 generations
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Docker: with iptables management disabled
  virtualisation.docker = {
    enable = true;
    daemon.settings.iptables = false;
  };

  # Secrets: decrypted at activation into /run/secrets
  sops = {
    defaultSopsFile = ../../../secrets/grimlock.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Install secrets from a systemd unit rather than the activation script.
    # The activation script path reloads units with systemctl, which NixOS
    # deprecated and removes in 26.11.
    useSystemdActivation = true;

    secrets = {
      pihole_admin_password.reloadUnits = [ "pihole-trusted.service" "pihole-restricted.service" ];

      # Whole-file secrets: written out verbatim and consumed as env files.
      "pihole-env-trusted" = {
        format = "binary";
        sopsFile = ../../../secrets/pihole-env-trusted;
        reloadUnits = [ "pihole-trusted.service" ];
      };

      "pihole-env-restricted" = {
        format = "binary";
        sopsFile = ../../../secrets/pihole-env-restricted;
        reloadUnits = [ "pihole-restricted.service" ];
      };

      "pihole-net" = {
        format = "binary";
        sopsFile = ../../../secrets/pihole-net;
        restartUnits = [ "docker-network-dns-lan.service" ];
      };
    };
  };

  # Unattended updates from the public flake. Nothing automerges, so this
  # only ever applies what has already been merged by hand.
  system.autoUpgrade = {
    enable = true;
    flake = "github:NuclearRedeye/homelab#grimlock";
    operation = "switch";

    # 04:00 rather than the 04:40 default: the reboot decision is taken after
    # the rebuild, and a run that overruns the window skips the reboot
    # silently. Starting at 04:00 leaves the rebuild 45 minutes to finish
    # inside the window C5 will set.
    dates = "04:00";
    randomizedDelaySec = "15min";

    # Drops --upgrade, which only means anything for channels. On a flake it
    # is inert and logs a warning on every run.
    upgrade = false;

    # No unattended reboots until the health gate and rollback exist.
    allowReboot = false;
  };

  users.motd = "grimlock: managed by the homelab flake";

  # Do not change after install: records the release this system was first built with
  system.stateVersion = "26.05";
}
