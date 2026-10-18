{ config, lib, pkgs, ... }:
{
  imports = [ ./disko.nix ../../modules/pihole.nix ];

  networking.hostName = "grimlock";
  networking.useDHCP = lib.mkDefault true;

  # Resolve via the EdgeRouter, never our own Pi-hole containers
  networking.nameservers = [ "192.168.11.1" ];

  # Prevent DHCP overwriting nameservers
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  time.timeZone = "Europe/London";

  # Hardware: Broadwell NUC (SATA = AHCI, USB 3 = xHCI)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Bootloader: UEFI + systemd-boot, keep the last 10 generations
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  services.fstrim.enabel = true;

  # Nix settings and housekeeping
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
    min-free = 5368709120; # When < 5GiB free space remains
    max-free = 16106127360; # collect garbage until >=15 GiB is free
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.optimise.automatic = true;

  # Admin user: key-only login, no password
  users.users.joel = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ../../keys/joel.id_rsa.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Docker: with iptables management disabled
  virtualisation.docker = {
    enable = true;
    daemon.settings.iptables = false;
  };

  # Secrets: decrypted at activation into /run/secrets
  sops = {
    defaultSopsFile = ../../../secrets/grimlock.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

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

  users.motd = "grimlock: managed by the homelab flake";

  # Do not change after install: records the release this system was first built with
  system.stateVersion = "26.05";
}
