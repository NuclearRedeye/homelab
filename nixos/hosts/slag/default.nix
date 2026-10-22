{ config, lib, pkgs, ... }:
{
  imports = [ ./disko.nix ../../modules/base.nix ];

  networking.hostName = "slag";
  networking.useDHCP = lib.mkDefault true;

  # Hardware: NUC5i3MYBE, Broadwell (SATA = AHCI, USB 3 = xHCI)
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Bootloader: UEFI + systemd-boot, keep the last 10 generations
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Half an hour after swoop, so the k3s nodes never upgrade together
  system.autoUpgrade.dates = "06:00";

  users.motd = "slag: managed by the homelab flake";

  # Do not change after install: records the release this system was first built with
  system.stateVersion = "26.05";
}
