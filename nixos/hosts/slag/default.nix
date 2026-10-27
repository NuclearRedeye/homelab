{ config, lib, pkgs, ... }:
{
  imports = [ ./disko.nix ../../modules/base.nix ../../modules/k3s.nix ];

  networking.hostName = "slag";
  networking.useDHCP = lib.mkDefault true;

  # Cluster traffic: tagged VLAN 100, unrouted, nodes only
  networking.vlans.cluster = { id = 100; interface = "enp0s25"; };
  networking.interfaces.cluster = {
    useDHCP = false;
    ipv4.addresses = [ { address = "10.0.100.41"; prefixLength = 24; } ];
  };

  # Hardware: NUC5i3MYBE, Broadwell (SATA = AHCI, USB 3 = xHCI)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Bootloader: UEFI + systemd-boot, keep the last 10 generations
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Secrets: decrypted into /run/secrets by a systemd unit
  sops = {
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    useSystemdActivation = true;
    secrets.k3s_token.sopsFile = ../../../secrets/k3s.yaml;
  };

  # Joins the cluster through snarl
  services.k3s.serverAddr = "https://snarl:6443";

  # Half an hour after swoop, so the k3s nodes never upgrade together
  system.autoUpgrade.dates = "06:00";

  users.motd = "slag: managed by the homelab flake";

  # Do not change after install: records the release this system was first built with
  system.stateVersion = "26.05";
}
