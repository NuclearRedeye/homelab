{ config, ... }:
{
  # Piraeus's own loader is disabled (#117), so the host provides DRBD 9
  boot.extraModulePackages = [ config.boot.kernelPackages.drbd ];
  boot.kernelModules = [
    "drbd"
    "drbd_transport_tcp"
    "dm_crypt"
    "dm_cache"
    "dm_writecache"
    "loop"
  ];
  boot.extraModprobeConfig = "options drbd usermode_helper=disabled";

  # Loads dm-thin-pool in the initrd and adds thin_check, so LVM activates the pool at boot (#141)
  services.lvm.boot.thin.enable = true;

  # Discards pass through ext4 and DRBD to the thin pool
  services.fstrim.enable = true;

  # LINSTOR satellite (TLS only, #119) and DRBD replication
  networking.firewall.interfaces.cluster.allowedTCPPortRanges = [
    { from = 3367; to = 3367; }
    { from = 7000; to = 7999; }
  ];
}
