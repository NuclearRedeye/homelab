{ config, lib, pkgs, ... }:
{
  imports = [ ./disko.nix ../../modules/base.nix ];

  networking.hostName = "snarl";
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

  # An hour after grimlock, leaving room to stagger the other k3s nodes
  system.autoUpgrade.dates = "05:00";

  users.motd = "snarl: managed by the homelab flake";

  # Do not change after install: records the release this system was first built with
  system.stateVersion = "26.05";
}
